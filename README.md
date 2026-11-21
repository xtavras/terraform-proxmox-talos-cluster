# terraform-proxmox-talos-cluster

OpenTofu/Terraform module that creates a [Talos Linux](https://www.talos.dev/)
Kubernetes cluster as VMs on a Proxmox VE node. A change to one variable runs
each day-2 operation: rolling Talos OS upgrades, Kubernetes upgrades and worker
scaling.

> [!WARNING]
> **This module is a proof of concept. Be very careful before you use it in production.**
>
> - It depends on pre-1.0 providers. The Talos provider marks
>   `ignore_kubernetes_upgrade_drift` as experimental.
> - All VMs run on one Proxmox node, so a host failure stops the whole cluster.
> - The state holds the cluster CA and secrets.
> - The tests in `tests/` mock both providers. They check the plan logic, not a
>   real Talos or Proxmox run.
>
> Pin an exact module version and review every `plan` before `apply`, version
> bumps most of all. Read [Limitations](#limitations) first.

## What it does

- Creates an [Image Factory](https://factory.talos.dev/) schematic with system
  extensions (`qemu-guest-agent` by default). Downloads the matching `nocloud`
  qcow2 image to Proxmox.
- Creates one VM per node. Each node gets a static IP from the Proxmox
  cloud-init drive.
- Creates and applies the Talos machine configs in the Talos >= 1.14
  multi-document format. Bootstraps etcd and returns `kubeconfig` and
  `talosconfig`.
- Shares an optional layer-2 VIP among the control planes for the Kubernetes API.
- A `talos_version` change runs a rolling OS upgrade, one node at a time: drain,
  reboot, wait for `Ready`, uncordon. VMs stay in place.
- A `kubernetes_version` change runs Talos `upgrade-k8s` with no reboots.

The module creates no CNI (unless `cni = "flannel"`), CSI, ingress or apps.
Install those with Helm or a GitOps tool such as Argo CD or Flux.

## Requirements

| Component | Version |
|---|---|
| OpenTofu or Terraform | >= 1.11, for ephemeral resources and write-only attributes |
| [bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox) | >= 0.123.1, < 1.0 |
| [siderolabs/talos](https://registry.terraform.io/providers/siderolabs/talos) | ~> 0.12.0 |
| Proxmox VE | >= 8.4, for the `import` content type on the image datastore |
| Talos | >= v1.14, for the multi-document machine config |

The caller configures both providers. The Proxmox API token must be allowed to
create VMs and to download files to the image datastore.

## Usage

```hcl
provider "proxmox" {
  endpoint = "https://192.168.1.10:8006/"
  # token from PROXMOX_VE_API_TOKEN
}

provider "talos" {}

module "cluster" {
  source  = "xtavras/talos-cluster/proxmox"
  version = "0.1.0"

  name               = "demo"
  talos_version      = "v1.14.3"
  kubernetes_version = "v1.35.10"

  proxmox = { node_name = "pve" }

  network = {
    cidr    = "192.168.1.0/24"
    gateway = "192.168.1.1"
    vip     = "192.168.1.30"
  }

  controlplane = { count = 3, cpu = 2, memory_mb = 2048, vm_id_start = 1001, ip_start = 31 }
  workers      = { count = 3, cpu = 4, memory_mb = 4096, vm_id_start = 1011, ip_start = 41 }
}

resource "local_sensitive_file" "kubeconfig" {
  content         = module.cluster.kubeconfig
  filename        = "${path.module}/generated/kubeconfig"
  file_permission = "0600"
}
```

Each pool numbers its nodes from 01:

| Node | VM ID | IP |
|---|---|---|
| `demo-cp-01` to `demo-cp-03` | 1001-1003 | 192.168.1.31-33 |
| `demo-w-01` to `demo-w-03` | 1011-1013 | 192.168.1.41-43 |

A node's IP is `cidrhost(network.cidr, ip_start + i)`. A pool can only grow into
free addresses and VM IDs after its range.

With the default `cni = "none"`, nodes stay `NotReady` until a CNI runs. Calico
on Talos needs `linuxDataplane: Nftables`, because Talos runs kube-proxy in
nftables mode. It also needs `kubeletVolumePluginPath: None` and
`flexVolumePath: None`, because `/usr` on Talos is read-only. See the
[Sidero Calico guide](https://docs.siderolabs.com/kubernetes-guides/cni/deploy-calico).

Examples:

- [`examples/basic`](examples/basic): 3 control planes with a VIP and 3 workers.
- [`examples/single-node`](examples/single-node): 1 control plane that also runs
  workloads, no VIP, flannel.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | `string` | required | Cluster name (DNS label). Also the VM tag and the default node name prefix |
| `node_name_prefix` | `string` | `name` | Node names are `<prefix>-cp-01`, `<prefix>-w-01` and so on |
| `talos_version` | `string` | required | Talos OS version, for example `v1.14.3`. A change runs a rolling upgrade |
| `kubernetes_version` | `string` | required | Kubernetes version, for example `v1.35.10`. A change runs `upgrade-k8s` |
| `talos_extensions` | `list(string)` | `["siderolabs/qemu-guest-agent"]` | Official system extensions |
| `controlplane` | `object` | required | `count` (1, 3 or 5, default 3), `cpu` (2), `memory_mb` (2048), `disk_gb` (20), `vm_id_start`, `ip_start` |
| `workers` | `object` | required | `count` (0 to 10, default 3), `cpu`, `memory_mb`, `disk_gb`, `vm_id_start`, `ip_start`. With `count = 0` the control planes run workloads |
| `network` | `object` | required | `cidr`, `gateway`, `dns_servers` (`[gateway]`), `vip` (`null` uses the first control plane IP), `bridge` (`vmbr0`), `vlan_id`, `mac_prefix` (`null` lets Proxmox assign MACs), `pod_cidr` (`10.244.0.0/16`), `service_cidr` (`10.96.0.0/12`) |
| `cni` | `string` | `"none"` | `"none"` or `"flannel"` |
| `kube_proxy` | `bool` | `true` | Set `false` only for a CNI that replaces kube-proxy |
| `proxmox` | `object` | required | `node_name`, `vm_datastore` (`local-lvm`), `image_datastore` (`local`, needs the `import` content type) |
| `config_patches` | `object` | `{}` | Extra Talos config patches as YAML strings: `all`, `controlplane`, `worker` |

The plan fails when the IP or VM ID ranges of the two pools overlap, or when
the VIP is also a node IP.

## Outputs

| Name | Description |
|---|---|
| `kubernetes_endpoint` | `https://<vip or first control plane>:6443` |
| `nodes` | Map of node name to `role`, `ip`, `vm_id`, `mac` |
| `controlplane_ips`, `worker_ips` | Lists of node IPs |
| `pod_cidr`, `service_cidr` | Kubernetes networks, for the CNI config |
| `talos_version`, `kubernetes_version` | Configured versions |
| `talos_config_contract` | Talos version the machine configs are generated for |
| `talos_installer_image`, `talos_schematic_id` | Image Factory results |
| `talosconfig` (sensitive) | `talosctl` client config with the `os:admin` role |
| `kubeconfig` (sensitive) | cluster-admin kubeconfig |
| `kubernetes_client_configuration` (sensitive) | Host, CA and client cert and key for the helm or kubernetes providers |

## Day-2 operations

- **Talos upgrade**: change `talos_version` by at most one minor version at a
  time. Nodes upgrade in place in the order `cp-01` to `cp-NN`, then `w-01` to
  `w-NN`. A failed node stops the chain. After the node is fixed, `apply`
  upgrades only the nodes that still run another version.
- **Config contract**: the machine configs use the config format of the
  `talos_version` the cluster was created with. `talos_machine_secrets` ignores
  later version changes, so upgrades keep the config format and the secrets.
- **Kubernetes upgrade**: change `kubernetes_version` by at most one minor
  version at a time. When both versions change in one `apply`, the OS upgrade
  runs first. The
  [Talos support matrix](https://docs.siderolabs.com/talos/latest/getting-started/support-matrix)
  lists the supported pairs.
- **Worker scaling**: new VMs boot the current image. Scaling down removes the
  workers with the highest numbers. Those nodes must be drained and deleted with
  `kubectl delete node` first.
- **CPU, RAM and disk changes** update the VM config without a reboot
  (`reboot_after_update = false`). Each changed node must be rebooted by hand,
  one at a time.
- **Manual Talos changes**: the module owns `talosctl upgrade`, `upgrade-k8s` and
  `apply-config`. The next `apply` reverts changes made with them by hand.

### Upgrade slots in `machines.tf`

Instances of one `for_each` resource cannot depend on each other. A `for_each`
over `talos_machine` would upgrade all nodes at the same time. `machines.tf`
therefore has one resource per slot (`cp_1` to `cp_5`, `w_1` to `w_10`). Each
slot has `count = 0` or `1` and `depends_on` on the slot before it.

More worker slots need three changes:

1. Run `scripts/gen-machines.sh <max_cp> <max_workers>`.
2. Raise the `workers.count` validation in `variables.tf`.
3. Add the new slots to `depends_on` of `talos_cluster.this` in `talos.tf`.

## Limitations

- All VMs run on one Proxmox node (`proxmox.node_name`).
- Fixed VM settings: `amd64`, `nocloud` platform, SeaBIOS with `q35`, `host` CPU
  type, one virtio NIC, IPv4, static IPs.
- The state holds the cluster CA and tokens. Use an encrypted backend or
  [OpenTofu state encryption](https://opentofu.org/docs/language/state/encryption/).
- Removing a node does not reset it, remove its etcd member or delete its
  Kubernetes node. A control plane must leave etcd with
  `talosctl etcd remove-member` before it is removed.
- A change to `network.mac_prefix`, `node_name_prefix`, `vm_id_start` or
  `ip_start` on an existing cluster replaces the affected VMs.
- At most 5 control planes and 10 workers, see
  [Upgrade slots](#upgrade-slots-in-machinestf).

### Known working versions

The module is used with this combination. Other versions are untested.

| Component | Version |
|---|---|
| Proxmox VE | 9.2, single node |
| Talos | v1.14.3, including the rolling upgrade from v1.14.1 |
| Kubernetes | v1.35.10 |
| OpenTofu | 1.13 |
| HashiCorp Terraform | 1.17, cluster creation |
| bpg/proxmox | 0.123.x |
| siderolabs/talos | 0.12.x |
| Calico | v3.33, nftables and VXLAN, installed separately |

## Development

```sh
tofu fmt -recursive
tofu init -backend=false && tofu validate
tofu test   # mocked providers, no Proxmox needed
```

## License

Apache License 2.0. Copyright 2026 Xtavras. See [LICENSE](LICENSE).
