# Smallest possible cluster: one schedulable control plane, no VIP, flannel.

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

# Auth from environment, see README "Proxmox API token":
#   export PROXMOX_VE_ENDPOINT='https://192.168.1.10:8006/'
#   export PROXMOX_VE_API_TOKEN='tofu@pve!tofu=<secret>'
provider "proxmox" {
  insecure = true # self-signed certificate
}

provider "talos" {}

module "cluster" {
  # Published: source = "xtavras/talos-cluster/proxmox"
  source = "../.."

  name               = "single"
  talos_version      = "v1.14.3"
  kubernetes_version = "v1.35.10"
  cni                = "flannel" # ready to use without installing a CNI

  proxmox = {
    node_name = "pve"
  }

  network = {
    cidr    = "192.168.1.0/24"
    gateway = "192.168.1.1"
  }

  controlplane = {
    count       = 1
    cpu         = 4
    memory_mb   = 4096
    vm_id_start = 1101
    ip_start    = 50
  }

  workers = {
    count       = 0 # control plane becomes schedulable
    vm_id_start = 1111
    ip_start    = 60
  }
}

output "kubeconfig" {
  value     = module.cluster.kubeconfig
  sensitive = true
}
