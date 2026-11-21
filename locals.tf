locals {
  prefix = coalesce(var.node_name_prefix, var.name)

  pools = {
    controlplane = merge(var.controlplane, { short = "cp" })
    worker       = merge(var.workers, { short = "w" })
  }

  # One entry per node; the list order is the rolling-upgrade order.
  node_list = flatten([
    for role in ["controlplane", "worker"] : [
      for i in range(local.pools[role].count) : {
        name      = format("%s-%s-%02d", local.prefix, local.pools[role].short, i + 1)
        role      = role
        vm_id     = local.pools[role].vm_id_start + i
        ip        = cidrhost(var.network.cidr, local.pools[role].ip_start + i)
        cpu       = local.pools[role].cpu
        memory_mb = local.pools[role].memory_mb
        disk_gb   = local.pools[role].disk_gb
        mac = var.network.mac_prefix == null ? null : upper(format("%s:%02x:%02x",
          var.network.mac_prefix,
          floor((local.pools[role].vm_id_start + i) / 256) % 256,
          (local.pools[role].vm_id_start + i) % 256,
        ))
      }
    ]
  ])

  nodes        = { for n in local.node_list : n.name => n }
  cp_names     = [for n in local.node_list : n.name if n.role == "controlplane"]
  worker_names = [for n in local.node_list : n.name if n.role == "worker"]

  controlplane_ips = [for k in local.cp_names : local.nodes[k].ip]
  worker_ips       = [for k in local.worker_names : local.nodes[k].ip]
  bootstrap_ip     = local.controlplane_ips[0]

  api_host         = coalesce(var.network.vip, local.bootstrap_ip)
  cluster_endpoint = "https://${local.api_host}:6443"
  prefix_length    = split("/", var.network.cidr)[1]
  dns_servers      = coalesce(var.network.dns_servers, [var.network.gateway])

  # VMs boot an already-installed nocloud image from scsi0.
  install_disk = "/dev/sda"
}
