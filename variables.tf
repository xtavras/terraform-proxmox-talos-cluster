# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

variable "name" {
  description = "Cluster name. Used for the Kubernetes cluster name, VM tags and (by default) the node name prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a lowercase DNS label (a-z, 0-9, '-')."
  }
}

variable "node_name_prefix" {
  description = "Prefix for node/VM names (<prefix>-cp-01, <prefix>-w-01, ...). Defaults to var.name."
  type        = string
  default     = null
}

variable "talos_version" {
  description = <<-EOT
    Talos OS version of all nodes. Changing it performs a rolling upgrade:
    control planes first, then workers, one node at a time, each node drained
    before its reboot. Upgrade one minor version at a time (v1.14.x -> v1.15.x).

    The machine-config contract is pinned automatically to the version the
    cluster was CREATED with (see talos_machine_secrets in talos.tf), so bumping
    this is always safe for the config format.
  EOT
  type        = string

  validation {
    condition     = can(regex("^v\\d+\\.\\d+\\.\\d+$", var.talos_version))
    error_message = "talos_version must look like v1.14.3."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version. Changing it runs Talos' upgrade-k8s (no reboots), after any Talos OS upgrade in the same apply. One minor at a time."
  type        = string

  validation {
    condition     = can(regex("^v\\d+\\.\\d+\\.\\d+$", var.kubernetes_version))
    error_message = "kubernetes_version must look like v1.35.10."
  }
}

variable "talos_extensions" {
  description = "Official Talos system extensions baked into the Image Factory schematic."
  type        = list(string)
  default     = ["siderolabs/qemu-guest-agent"]
}

# ---------------------------------------------------------------------------
# Node pools
# ---------------------------------------------------------------------------

variable "controlplane" {
  description = <<-EOT
    Control plane pool. Node i (0-based) gets:
      name  = <prefix>-cp-<i+1, 2 digits>
      vm_id = vm_id_start + i
      ip    = cidrhost(network.cidr, ip_start + i)
    Scale DOWN only from the end, and remove the etcd member first.
  EOT
  type = object({
    count       = optional(number, 3)
    cpu         = optional(number, 2)
    memory_mb   = optional(number, 2048)
    disk_gb     = optional(number, 20)
    vm_id_start = number
    ip_start    = number
  })

  validation {
    condition     = contains([1, 3, 5], var.controlplane.count)
    error_message = "controlplane.count must be 1, 3 or 5 (etcd quorum)."
  }
}

variable "workers" {
  description = <<-EOT
    Worker pool, same numbering scheme as controlplane (<prefix>-w-01, ...).
    count = 0 makes the control planes schedulable. Scaling down removes the
    highest-numbered workers; drain/delete them in Kubernetes first.
  EOT
  type = object({
    count       = optional(number, 3)
    cpu         = optional(number, 2)
    memory_mb   = optional(number, 2048)
    disk_gb     = optional(number, 20)
    vm_id_start = number
    ip_start    = number
  })

  validation {
    # Upper bound = number of talos_machine.w_* slots in machines.tf.
    # Raise it with scripts/gen-machines.sh.
    condition     = var.workers.count >= 0 && var.workers.count <= 10
    error_message = "workers.count must be between 0 and 10 (see scripts/gen-machines.sh to add slots)."
  }
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "network" {
  description = <<-EOT
    Node network and Kubernetes networking.
      cidr          node network; node IPs are cidrhost(cidr, <pool>.ip_start + i)
      gateway       default gateway of the nodes
      dns_servers   defaults to [gateway]
      dns_domain    cloud-init search domain. Proxmox copies the host's search
                    domain when it's empty, so the default is "invalid", a
                    name reserved by RFC 2606. Talos doesn't use it.
      vip           shared layer-2 VIP for the Kubernetes API (needs >1 CP to
                    make sense). null = use the first control plane IP.
      bridge        Proxmox bridge
      vlan_id       VLAN tag on the VM NIC (null = untagged)
      mac_prefix    first 4 octets for deterministic MACs, e.g. "BC:24:11:00":
                    MAC = <prefix>:<vm_id as 2 bytes>. null = Proxmox assigns
                    a random MAC at creation (stable for the VM's lifetime).
                    Changing it on an existing cluster changes every NIC.
      pod_cidr      must match the CNI's IP pool (e.g. Calico)
      service_cidr  Kubernetes service network
  EOT
  type = object({
    cidr         = string
    gateway      = string
    dns_servers  = optional(list(string))
    dns_domain   = optional(string, "invalid")
    vip          = optional(string)
    bridge       = optional(string, "vmbr0")
    vlan_id      = optional(number)
    mac_prefix   = optional(string)
    pod_cidr     = optional(string, "10.244.0.0/16")
    service_cidr = optional(string, "10.96.0.0/12")
  })

  validation {
    condition     = var.network.mac_prefix == null || can(regex("^([0-9A-Fa-f]{2}:){3}[0-9A-Fa-f]{2}$", coalesce(var.network.mac_prefix, "-")))
    error_message = "network.mac_prefix must be 4 octets like \"BC:24:11:00\"."
  }
}

variable "cni" {
  description = <<-EOT
    "none":    no CNI from Talos (install Calico/Cilium yourself, e.g. Helm/Argo CD).
               Nodes stay NotReady until a CNI is installed.
    "flannel": Talos' built-in flannel.
  EOT
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "flannel"], var.cni)
    error_message = "cni must be \"none\" or \"flannel\"."
  }
}

variable "kube_proxy" {
  description = "Run Talos' kube-proxy (nftables mode). Set false only for a CNI that replaces kube-proxy (e.g. Cilium/Calico eBPF)."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Proxmox
# ---------------------------------------------------------------------------

variable "proxmox" {
  description = <<-EOT
    Placement on Proxmox. The proxmox provider itself is configured by the caller.
      node_name        PVE node the VMs run on
      vm_datastore     VM disks + cloud-init drives
      image_datastore  downloaded Talos qcow2 (needs the 'import' content type, PVE >= 8.4)
  EOT
  type = object({
    node_name       = string
    vm_datastore    = optional(string, "local-lvm")
    image_datastore = optional(string, "local")
  })
}

# ---------------------------------------------------------------------------
# Extra config patches
# ---------------------------------------------------------------------------

variable "config_patches" {
  description = <<-EOT
    Extra Talos machine-config patches (YAML strings, e.g. yamlencode({...})),
    appended after the module's own patches.
      all           every node
      controlplane  control plane nodes only
      worker        worker nodes only
  EOT
  type = object({
    all          = optional(list(string), [])
    controlplane = optional(list(string), [])
    worker       = optional(list(string), [])
  })
  default = {}
}
