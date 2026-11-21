# Changelog

All notable changes to this module are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/). Before 1.0.0, minor versions may
contain breaking changes.

## [0.1.0] - Unreleased

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
