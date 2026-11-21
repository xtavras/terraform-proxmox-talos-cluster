# Plan-only unit tests with mocked providers: no Proxmox host or network needed.
#   tofu init && tofu test

mock_provider "proxmox" {
  # The VM validates import_from as "<datastore>:import/<file>".
  mock_resource "proxmox_download_file" {
    defaults = {
      id = "local:import/talos-mock.qcow2"
    }
  }
}
mock_provider "talos" {}

variables {
  name               = "test"
  talos_version      = "v1.14.3"
  kubernetes_version = "v1.35.10"
  proxmox            = { node_name = "pve" }
  network = {
    cidr    = "10.0.0.0/24"
    gateway = "10.0.0.1"
    vip     = "10.0.0.30"
    # Mocks can't fill in the Proxmox-assigned MAC (a computed attribute of a
    # configured block), so the tests use deterministic MACs.
    mac_prefix = "BC:24:11:00"
  }
  controlplane = { count = 3, vm_id_start = 1001, ip_start = 31 }
  workers      = { count = 2, vm_id_start = 1011, ip_start = 41 }
}

run "node_layout" {
  command = plan

  assert {
    condition     = output.controlplane_ips == ["10.0.0.31", "10.0.0.32", "10.0.0.33"]
    error_message = "unexpected control plane IPs: ${jsonencode(output.controlplane_ips)}"
  }
  assert {
    condition     = output.worker_ips == ["10.0.0.41", "10.0.0.42"]
    error_message = "unexpected worker IPs: ${jsonencode(output.worker_ips)}"
  }
  assert {
    condition     = output.kubernetes_endpoint == "https://10.0.0.30:6443"
    error_message = "endpoint should use the VIP"
  }
  assert {
    condition = toset(keys(proxmox_virtual_environment_vm.node)) == toset([
      "test-cp-01", "test-cp-02", "test-cp-03", "test-w-01", "test-w-02",
    ])
    error_message = "unexpected node names"
  }
  assert {
    condition     = proxmox_virtual_environment_vm.node["test-w-02"].vm_id == 1012
    error_message = "unexpected VM ID for test-w-02"
  }
  assert {
    condition     = length(talos_machine.cp_3) == 1 && length(talos_machine.cp_4) == 0
    error_message = "control plane slots: cp_1..cp_3 used, cp_4 unused"
  }
  assert {
    condition     = length(talos_machine.w_2) == 1 && length(talos_machine.w_3) == 0
    error_message = "worker slots: w_1..w_2 used, w_3 unused"
  }
}

run "deterministic_mac" {
  command = plan

  assert {
    # vm_id 1012 = 0x03F4
    condition     = output.nodes["test-w-02"].mac == "BC:24:11:00:03:F4"
    error_message = "unexpected MAC: ${output.nodes["test-w-02"].mac}"
  }
}

run "rejects_bad_mac_prefix" {
  command = plan

  variables {
    network = { cidr = "10.0.0.0/24", gateway = "10.0.0.1", mac_prefix = "BC:24:11" }
  }

  expect_failures = [var.network]
}

run "no_vip_uses_first_controlplane" {
  command = plan

  variables {
    network      = { cidr = "10.0.0.0/24", gateway = "10.0.0.1", mac_prefix = "BC:24:11:00" }
    controlplane = { count = 1, vm_id_start = 1001, ip_start = 31 }
    workers      = { count = 0, vm_id_start = 1011, ip_start = 41 }
  }

  assert {
    condition     = output.kubernetes_endpoint == "https://10.0.0.31:6443"
    error_message = "endpoint should fall back to the first control plane"
  }
}

run "node_name_prefix" {
  command = plan

  variables {
    node_name_prefix = "k8s"
  }

  assert {
    condition     = contains(keys(proxmox_virtual_environment_vm.node), "k8s-cp-01")
    error_message = "node_name_prefix not applied"
  }
}

run "rejects_even_controlplane_count" {
  command = plan

  variables {
    controlplane = { count = 2, vm_id_start = 1001, ip_start = 31 }
  }

  expect_failures = [var.controlplane]
}

run "rejects_too_many_workers" {
  command = plan

  variables {
    workers = { count = 11, vm_id_start = 1011, ip_start = 41 }
  }

  expect_failures = [var.workers]
}

run "rejects_bad_version" {
  command = plan

  variables {
    talos_version = "1.14.3"
  }

  expect_failures = [var.talos_version]
}

run "rejects_overlapping_ips" {
  command = plan

  variables {
    workers = { count = 2, vm_id_start = 1011, ip_start = 32 }
  }

  expect_failures = [talos_machine_secrets.this]
}

run "rejects_vip_on_node_ip" {
  command = plan

  variables {
    network = { cidr = "10.0.0.0/24", gateway = "10.0.0.1", vip = "10.0.0.31", mac_prefix = "BC:24:11:00" }
  }

  expect_failures = [talos_machine_secrets.this]
}

run "rejects_overlapping_vm_ids" {
  command = plan

  variables {
    workers = { count = 2, vm_id_start = 1002, ip_start = 41 }
  }

  expect_failures = [talos_machine_secrets.this]
}

run "vm_tags_and_dns_domain" {
  command = plan

  # The cluster name equals the fixed "talos" tag.
  variables {
    name = "talos"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.node["talos-cp-01"].tags == tolist(["talos", "controlplane"])
    error_message = "tags must not repeat: ${jsonencode(proxmox_virtual_environment_vm.node["talos-cp-01"].tags)}"
  }
  assert {
    condition     = proxmox_virtual_environment_vm.node["talos-w-01"].initialization[0].dns[0].domain == "invalid"
    error_message = "cloud-init DNS domain must be set, or Proxmox copies the host's"
  }
}
