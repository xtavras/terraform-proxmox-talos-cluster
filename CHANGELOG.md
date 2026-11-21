# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). Before 1.0.0, minor versions may
contain breaking changes.

## [Unreleased]

### Changed

- `network.mac_prefix` accepts the 8 hex digits with or without separators:
  `"DE:AD:BE:EF"`, `"dead:beef"` and `"deadbeef"` are the same prefix. A
  multicast prefix (odd first octet) fails validation.
- README: changing `mac_prefix` on a running cluster updates the VMs in place,
  it doesn't replace them. Changing `ip_start` is not supported on a running
  cluster.

### Fixed

- VM tags no longer contain duplicates. With `name = "talos"`, Proxmox dropped
  the duplicate tag and every plan showed a change.
- The cloud-init drive no longer gets the Proxmox host's DNS search domain. New
  input `network.dns_domain`, default `invalid` (RFC 2606). On an existing
  cluster, the next apply updates the cloud-init drive of every VM in place,
  without a reboot.
- The reboot advice for CPU, RAM and disk changes: `qm reboot`, not
  `talosctl reboot`, which doesn't apply pending Proxmox changes.

## [0.1.0] - 2026-11-21

First public release (proof of concept).

### Added

- Proxmox VMs from an Image Factory `nocloud` qcow2 image, with a static IP for
  each node through cloud-init.
- Control plane and worker pools (`count`, `cpu`, `memory_mb`, `disk_gb`,
  `vm_id_start`, `ip_start`).
- Talos >= 1.14 multi-document machine config, an optional layer-2 VIP, and
  `cni` = `none`/`flannel`, `kube_proxy` toggle and extra `config_patches`.
- Rolling Talos OS upgrades, one node at a time, through chained `talos_machine`
  slots (5 control plane, 10 worker).
- Kubernetes upgrades through `talos_cluster` (`upgrade-k8s`).
- Config contract frozen at creation.
- Optional deterministic MACs (`network.mac_prefix`).
- Outputs: `kubeconfig`, `talosconfig`, client configuration, nodes.
- Plan-only unit tests with mocked providers.
