terraform {
  # OpenTofu or Terraform >= 1.11: ephemeral resources + write-only attributes (drain kubeconfig is
  # handed to talos_machine without being stored in state).
  required_version = ">= 1.11.0"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # Pre-1.0: minor releases can break. Tested with 0.123.x.
      version = ">= 0.123.1, < 1.0.0"
    }
    talos = {
      source = "siderolabs/talos"
      # 0.12 introduced talos_machine (config + OS upgrades) and talos_cluster
      # (bootstrap + upgrade-k8s). Pre-1.0: keep the pin tight.
      version = "~> 0.12.0"
    }
  }
}
