output "name" {
  value = var.name
}

output "kubernetes_endpoint" {
  description = "Kubernetes API URL (VIP, or the first control plane if no VIP)."
  value       = local.cluster_endpoint
}

output "talos_version" {
  value = var.talos_version
}

output "kubernetes_version" {
  value = var.kubernetes_version
}

output "talos_config_contract" {
  description = "Config-generation contract, frozen at cluster creation."
  value       = local.talos_config_contract
}

output "talos_schematic_id" {
  value = talos_image_factory_schematic.this.id
}

output "talos_installer_image" {
  value = local.talos_installer_image
}

output "pod_cidr" {
  description = "Pod network; the CNI's IP pool must match."
  value       = var.network.pod_cidr
}

output "service_cidr" {
  value = var.network.service_cidr
}

output "nodes" {
  description = "Nodes by name, in rolling-upgrade order of their talos_machine slots."
  value = {
    for k, n in local.nodes : k => {
      role  = n.role
      ip    = n.ip
      vm_id = n.vm_id
      mac   = n.mac != null ? n.mac : proxmox_virtual_environment_vm.node[k].network_device[0].mac_address
    }
  }
}

output "controlplane_ips" {
  value = local.controlplane_ips
}

output "worker_ips" {
  value = local.worker_ips
}

output "talosconfig" {
  description = "talosctl client config (os:admin)."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "kubeconfig" {
  description = "cluster-admin kubeconfig (raw YAML)."
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "kubernetes_client_configuration" {
  description = "host / CA / client cert+key, e.g. for the helm/kubernetes providers."
  value       = talos_cluster_kubeconfig.this.kubernetes_client_configuration
  sensitive   = true
}
