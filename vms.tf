resource "proxmox_virtual_environment_vm" "node" {
  for_each = local.nodes

  node_name   = var.proxmox.node_name
  vm_id       = each.value.vm_id
  name        = each.key
  description = "Talos ${each.value.role} of cluster ${var.name} (managed by OpenTofu)"
  # distinct: Proxmox drops duplicate tags, which would show as a
  # change in every plan (e.g. name = "talos").
  tags = distinct(["talos", var.name, each.value.role])

  on_boot         = true
  started         = true
  stop_on_destroy = true
  # Never let the provider reboot nodes on its own (e.g. after a CPU/RAM
  # change): reboots must be rolling. Restart changed VMs one at a time with
  # 'qm reboot <vm_id>'. 'talosctl reboot' uses kexec inside the running VM,
  # so Proxmox never applies the pending change.
  reboot_after_update = false

  machine       = "q35"
  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"

  operating_system {
    type = "l26"
  }

  cpu {
    type  = "host" # Talos needs x86-64-v2+
    cores = each.value.cpu
  }

  memory {
    dedicated = each.value.memory_mb
    floating  = 0 # no ballooning
  }

  agent {
    enabled = true
    timeout = "2m"
    # The guest agent (Talos extension) only starts once a machine config is
    # applied; don't block VM creation waiting for agent-reported IPs.
    wait_for_ip {
      disabled = true
    }
  }

  disk {
    datastore_id = var.proxmox.vm_datastore
    interface    = "scsi0"
    import_from  = proxmox_download_file.talos.id
    file_format  = "raw"
    size         = each.value.disk_gb
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  # mac_address null (no network.mac_prefix): Proxmox assigns one at creation
  # and keeps it for the VM's lifetime. talos.tf uses it for the net0 alias.
  network_device {
    bridge      = var.network.bridge
    model       = "virtio"
    vlan_id     = var.network.vlan_id
    mac_address = each.value.mac
  }

  # Cloud-init drive -> Talos 'nocloud' picks up the static IP in maintenance
  # mode, so the machine config can be pushed to a known address.
  initialization {
    datastore_id = var.proxmox.vm_datastore
    ip_config {
      ipv4 {
        address = "${each.value.ip}/${local.prefix_length}"
        gateway = var.network.gateway
      }
    }
    dns {
      servers = local.dns_servers
      # Without a domain, Proxmox copies the host's search domain.
      domain = var.network.dns_domain
    }
  }

  boot_order = ["scsi0"]

  lifecycle {
    # The boot image only matters at creation; afterwards talos_machine owns
    # the OS version.
    ignore_changes = [
      disk[0].import_from,
    ]
  }
}
