# 3 control planes behind a layer-2 VIP + 3 workers on one Proxmox node.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.123.1"
    }
    talos = {
      source  = "siderolabs/talos"
      version = "~> 0.12.0"
    }
  }
}

provider "proxmox" {
  endpoint = "https://192.168.1.10:8006/"
  # API token from PROXMOX_VE_API_TOKEN ("user@realm!tokenid=secret").
  insecure = true # self-signed PVE certificate
}

provider "talos" {}

module "cluster" {
  # Published: source = "xtavras/talos-cluster/proxmox"
  source = "../.."

  name               = "demo"
  talos_version      = "v1.14.3"
  kubernetes_version = "v1.35.10"

  proxmox = {
    node_name = "pve"
  }

  network = {
    cidr    = "192.168.1.0/24"
    gateway = "192.168.1.1"
    vip     = "192.168.1.30"
  }

  controlplane = {
    count       = 3
    vm_id_start = 1001 # 1001-1003
    ip_start    = 31   # 192.168.1.31-33
  }

  workers = {
    count       = 3
    cpu         = 4
    memory_mb   = 4096
    vm_id_start = 1011 # 1011-1013
    ip_start    = 41   # 192.168.1.41-43
  }
}

output "kubernetes_endpoint" {
  value = module.cluster.kubernetes_endpoint
}

output "nodes" {
  value = module.cluster.nodes
}

output "kubeconfig" {
  value     = module.cluster.kubeconfig
  sensitive = true
}

output "talosconfig" {
  value     = module.cluster.talosconfig
  sensitive = true
}
