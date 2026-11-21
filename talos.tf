# ---------------------------------------------------------------------------
# Secrets (CA, tokens, ...). Live in state: protect the state file.
#
# talos_version here is the config-generation CONTRACT. It is taken from
# var.talos_version once, at creation, and then frozen (ignore_changes), so
# later talos_version bumps upgrade the OS without changing the config format
# or regenerating secrets. Never change the contract's minor version on a
# running cluster.
# ---------------------------------------------------------------------------

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version

  lifecycle {
    ignore_changes = [talos_version]

    precondition {
      condition     = length(distinct([for n in local.node_list : n.ip])) == length(local.node_list)
      error_message = "Node IP ranges of controlplane and workers overlap (check ip_start/count)."
    }
    precondition {
      condition     = var.network.vip == null || !contains([for n in local.node_list : n.ip], coalesce(var.network.vip, "-"))
      error_message = "network.vip must not be one of the node IPs."
    }
    precondition {
      condition     = length(distinct([for n in local.node_list : n.vm_id])) == length(local.node_list)
      error_message = "VM ID ranges of controlplane and workers overlap (check vm_id_start/count)."
    }
  }
}

locals {
  talos_config_contract = talos_machine_secrets.this.talos_version
}

# ---------------------------------------------------------------------------
# Machine configuration, one per node (hostname + NIC alias are per node).
# Talos >= 1.14 multi-document format: each patch merges into the generated
# document of the same kind.
# ---------------------------------------------------------------------------

data "talos_machine_configuration" "node" {
  for_each = local.nodes

  cluster_name     = var.name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = each.value.role
  machine_secrets  = talos_machine_secrets.this.machine_secrets

  talos_version = local.talos_config_contract
  # Only used for freshly created nodes; running clusters are upgraded by
  # talos_cluster.kubernetes_version (upgrade-k8s).
  kubernetes_version = var.kubernetes_version

  config_patches = concat(
    [
      # VMs boot an already-installed nocloud image, so nothing is installed
      # at boot. This records the installer (= upgrade target) and disk.
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "UnattendedInstallConfig"
        installer = {
          image = local.talos_installer_image
        }
        provisioning = {
          diskSelector = {
            match = "disk.dev_path == \"${local.install_disk}\""
          }
          wipe = false
        }
      }),
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "KubeNodeConfig"
        nodeIP = {
          validSubnets = [var.network.cidr]
        }
      }),
      yamlencode({
        apiVersion     = "v1alpha1"
        kind           = "KubeNetworkConfig"
        podSubnets     = [var.network.pod_cidr]
        serviceSubnets = [var.network.service_cidr]
      }),
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "HostnameConfig"
        auto       = "off"
        hostname   = each.key
      }),
      # Stable NIC name regardless of kernel naming; the VIP is bound to it.
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "LinkAliasConfig"
        name       = "net0"
        selector = {
          match = "mac(link.permanent_addr) == \"${lower(each.value.mac != null ? each.value.mac : proxmox_virtual_environment_vm.node[each.key].network_device[0].mac_address)}\""
        }
      }),
    ],

    # Control plane only: these documents exist only in control plane configs.
    each.value.role == "controlplane" ? concat(
      var.cni == "none" ? [
        # Talos >= 1.14 way to disable the built-in flannel.
        yamlencode({
          apiVersion = "v1alpha1"
          kind       = "KubeFlannelCNIConfig"
          "$patch"   = "delete"
        }),
      ] : [],
      var.kube_proxy ? [] : [
        yamlencode({
          apiVersion = "v1alpha1"
          kind       = "KubeProxyConfig"
          "$patch"   = "delete"
        }),
      ],
      var.network.vip == null ? [] : [
        # Floating API endpoint, announced via gratuitous ARP by one CP at a time.
        yamlencode({
          apiVersion = "v1alpha1"
          kind       = "Layer2VIPConfig"
          name       = var.network.vip
          link       = "net0"
        }),
      ],
      var.workers.count > 0 ? [] : [
        # No workers: let workloads run on the control planes.
        yamlencode({
          apiVersion = "v1alpha1"
          kind       = "KubeNodeConfig"
          taints = {
            "node-role.kubernetes.io/control-plane" = { "$patch" = "delete" }
          }
        }),
      ],
      var.config_patches.controlplane,
    ) : var.config_patches.worker,

    var.config_patches.all,
  )
}

# ---------------------------------------------------------------------------
# Kubeconfig for talos_machine to cordon/drain nodes during OS upgrades.
# Ephemeral + write-only: derived offline from the secrets, never stored.
# ---------------------------------------------------------------------------

ephemeral "talos_cluster_kubeconfig" "drain" {
  cluster_name    = var.name
  machine_secrets = talos_machine_secrets.this.machine_secrets
  endpoint        = local.cluster_endpoint
}

# ---------------------------------------------------------------------------
# Cluster: etcd bootstrap (once) + Kubernetes version (upgrade-k8s on change).
# Depends on every machine slot, so a combined Talos + Kubernetes bump rolls
# the OS first, then upgrades Kubernetes.
# ---------------------------------------------------------------------------

resource "talos_cluster" "this" {
  depends_on = [
    talos_machine.cp_1, talos_machine.cp_2, talos_machine.cp_3, talos_machine.cp_4, talos_machine.cp_5,
    talos_machine.w_1, talos_machine.w_2, talos_machine.w_3, talos_machine.w_4, talos_machine.w_5,
    talos_machine.w_6, talos_machine.w_7, talos_machine.w_8, talos_machine.w_9, talos_machine.w_10,
  ]

  node                 = local.bootstrap_ip
  control_plane_nodes  = local.controlplane_ips
  client_configuration = talos_machine_secrets.this.client_configuration
  kubernetes_version   = var.kubernetes_version
}

# ---------------------------------------------------------------------------
# Client configs (returned as sensitive outputs; the caller decides where to
# write them).
# ---------------------------------------------------------------------------

data "talos_client_configuration" "this" {
  cluster_name         = var.name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.controlplane_ips
  # Default target node only: avoids an accidental cluster-wide 'talosctl upgrade'.
  nodes = [local.bootstrap_ip]
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_cluster.this]

  node                 = local.bootstrap_ip
  client_configuration = talos_machine_secrets.this.client_configuration
}
