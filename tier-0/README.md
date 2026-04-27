# Tier-0 Robustness Test Workflow

Boundary: **Add Tier-0 robustness test workflow**

This archive contains a distro-agnostic unit/integration harness for the `_404` Tier-0 control plane. It is meant to be overlaid into the dotfiles repo and executed in both Debian-base and Arch-base distrobox containers.

## Contract

The suite answers one question:

> Can this machine recover, diagnose, and validate the control plane from a clean shell?

It intentionally does **not** validate app convergence.

## Scope

Covered phases:

1. clean shell load
2. shell transition checks
3. PATH/tool resolution
4. lint/precommit gate
5. audit gate
6. doctor graph gate
7. bootstrap dry-run
8. git substrate refresh/status
9. aggregate `dotctl check`

Allowed operations:

- observe
- vet
- dry-run
- syntax check
- PATH resolution
- tool version probes
- temporary fixture writes under an isolated `$HOME`

Avoided operations:

- real remediation
- home activation
- git commit/push/pull against the live repo
- package installation
- display/session mutation
- `systemctl restart`
- `loginctl` mutation

## Repository overlay

From the extracted archive root:

```sh
cp -a tests /path/to/_404/
cp Justfile.tier0-snippet /path/to/_404/
```

Optional Justfile integration:

```make
# paste from Justfile.tier0-snippet
```

## Direct execution

From the dotfiles repo root:

```sh
./tests/tier0/run.sh --all
```

Run only one backend:

```sh
./tests/tier0/run.sh --phases
./tests/tier0/run.sh --bats
./tests/tier0/run.sh --shellspec
```

The runner creates an isolated temporary `$HOME`, copies only the Tier-0/control-plane subset, initializes a local Git fixture, and installs a test-local `dotctl`/`yadm` adapter in `$TOOL_PATH_HOME`. The adapters are unit-test shims for the control-plane libraries, not production replacements.

When phases run, the harness also writes matrix artifacts to a predictable report directory. By default that is `./.tier0-results/` from the repo root, with files named like `tier0-robustness-debian-base.json` and `tier0-robustness-debian-base.log`. Override with `TIER0_REPORT_DIR` if needed.

## Distrobox matrix

Expected existing containers:

- `tier0-debian`
- `tier0-arch`

Run:

```sh
./tests/tier0/scripts/distrobox-matrix.sh
just test-tier0-matrix
```

Override names:

```sh
TIER0_DEBIAN_CONTAINER=my-debian TIER0_ARCH_CONTAINER=my-arch ./tests/tier0/scripts/distrobox-matrix.sh
```

The matrix script does not create containers and does not install packages. It only enters existing distrobox containers and runs the suite.

## Required tools inside each test container

Hard requirements:

- `bash`
- `zsh`
- `git`
- `jq`
- `cue`
- `just`
- `python3`
- `shellcheck`
- `shfmt`
- `shellharden`
- `bats`
- `shellspec`
- `timeout` from GNU coreutils

Optional probes used by doctor may be absent or degraded without failing the unit fixture:

- `loginctl`
- `systemctl`
- `busctl`
- `ip`
- `getent`
- `kitty`
- `xdpyinfo`
- `xset`

## Modes

Default is `unit` mode:

```sh
TIER0_MODE=unit ./tests/tier0/run.sh --all
```

Unit mode uses fixture adapters for `dotctl` and `yadm` so the tests can run against a temporary `$HOME` without depending on a live yadm checkout.

Integration mode is reserved for a live machine with real projected tools:

```sh
TIER0_MODE=integration ./tests/tier0/run.sh --phases
```

Use integration mode only after the unit matrix passes in both distro families.
