# AGENTS.md

OpenTofu module: Talos Kubernetes cluster as VMs on one Proxmox VE node, with
rolling Talos/Kubernetes upgrades. Published as `xtavras/talos-cluster/proxmox`.
Proof of concept: the README's warning stays at the top.

## Check loop

Run with `tofu` (the target and CI tool). Every change ends **green** on:

```sh
tofu fmt -recursive && tofu init -backend=false && tofu validate && tofu test
```

`tofu test` is plan-only with mocked providers: it proves layout, validation
and preconditions, never Talos or Proxmox runtime behaviour. A change to the
machine config (`talos.tf`) or VM settings (`vms.tf`) is verified by an apply
against a real Proxmox host before release; say so when that hasn't happened.

## Upgrade slots

`machines.tf` is **generated**: edit `scripts/gen-machines.sh` and regenerate
(CI fails on drift). One `talos_machine` per slot, chained by `depends_on`,
because `for_each` instances can't depend on each other and would upgrade all
nodes at once. Changing slot counts touches three places together:
`gen-machines.sh` arguments, the `workers.count` validation in `variables.tf`,
and `talos_cluster.this` `depends_on` in `talos.tf`.

## Invariants on running clusters

Users apply new module versions to live clusters, so plan every change as an
**upgrade**, not a fresh install:

- **Contract**: `talos_machine_secrets.talos_version` with
  `ignore_changes` freezes the config-generation contract at creation. Keep it;
  dropping it regenerates secrets or changes the config format on upgrade.
- **Identity**: node names, `vm_id`, IPs and MACs derive from pool inputs.
  A changed name or `vm_id` replaces VMs, a changed IP strands running nodes,
  and a changed MAC swaps all NICs at once. Any change to that derivation is a
  **breaking** change.
- **Reboots** belong to Talos: VMs keep `reboot_after_update = false` and
  `ignore_changes = [disk[0].import_from]`.
- A machine-config change re-applies to every node; state the expected plan
  (in-place updates, zero replacements) in the change description.

## Talos config patches

Talos >= 1.14 multi-document format: each patch is a typed document
(`KubeNodeConfig`, `LinkAliasConfig` and so on) merged into the generated one;
removal uses `$patch: delete`. Before writing a new patch, confirm its effect
with `talosctl gen config <name> https://1.2.3.4:6443 --talos-version v1.14
--config-patch-control-plane @patch.yaml` and inspect the output.

## Scope

The module stops at a bootstrapped cluster. CNI (beyond Talos' flannel), CSI,
ingress and apps live with the user's Helm/GitOps tooling.

## Mocked tests

Mocks cannot fill computed attributes inside configured blocks, so the
Proxmox-assigned MAC is null under test: the shared test variables set
`network.mac_prefix`. `proxmox_download_file.id` is mocked as
`local:import/<file>` because the VM validates `import_from`.

## Docs and releases

- README Inputs/Outputs tables are hand-written: update them with every
  variable or output change.
- Every user-visible change gets a `CHANGELOG.md` entry under `Unreleased`;
  pre-1.0, breaking changes bump the minor version.
- Releases are `vX.Y.Z` git tags; both registries pick tags up from GitHub.
- README "Known working versions" lists only combinations a real apply has
  run with; update it at each release.
- Examples and tests use generic values (`192.168.1.0/24`, node `pve`,
  cluster `demo`), never a real environment's.
