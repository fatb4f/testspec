# `_404-main.zip` crawl notes

## Tier-0 control-plane files found

Shell substrate:

- `.config/shell/load-env.sh`
- `.config/shell/env.d/*.sh`
- `.config/shell/validate-env.sh`
- `.config/shell/tier0-check.sh`
- `.config/shell/lint-shell.sh`
- `.config/shell/policy/lint/*.cue`

Operator/controller entry points:

- `Justfile`
- `check-tier0`
- `lint-shell`
- `precommit-lint`
- `check-bootstrap`
- `check`

Dotctl adapter substrate:

- `.config/dotctl/src/bashly.yml`
- `.config/dotctl/src/*_command.sh`
- `.config/dotctl/src/lib/*.sh`
- `.config/dotctl/src/lib/handler/*.sh`
- `.config/dotctl/policy/{doctor,git,substrate}.cue`

Bootstrap substrate:

- `.config/yadm/bootstrap`
- `.config/yadm/bootstrap.d/{00-common,10-host,20-dirs,30-system,40-userland,50-projectors,90-validate}.sh`

Audit substrate:

- `.config/dotfiles-audit/policy/dotfiles_audit.cue`

Zsh login substrate:

- `.zshenv`
- `.zprofile`
- `.zshrc`
- `.config/zsh/.zshenv`
- `.config/zsh/.zprofile`
- `.config/zsh/.zshrc`

## Current command surface

Observed current commands:

```sh
"$HOME/.config/shell/tier0-check.sh"
"$HOME/.config/shell/validate-env.sh"
just precommit-lint
dotctl audit run
dotctl doctor --json
DRY_RUN=1 HOST_CLASS="${HOST_CLASS:-debian-base}" yadm bootstrap
dotctl git refresh
dotctl check
```

Current Bashly shape has `dotctl doctor` with `--json`; it does not yet define `dotctl doctor check` as a subcommand.

## Test boundary selected

The archive tests the control-plane libraries through a temporary `$HOME` fixture and a local test adapter. This keeps the suite distro-agnostic and read-only relative to the live checkout while still exercising the same CUE, shell, audit, doctor, bootstrap, and git substrate paths.

## High-signal potential issues this should catch

- missing required toolchain pieces in one distro family
- clean bash/zsh environment load regressions
- login zsh network/bootstrap hangs; fixture pre-seeds a stub Zim cache to keep the test offline
- projected PATH failures
- CUE shell lint policy mismatch
- audit allowlist drift
- doctor graph schema drift
- bootstrap dry-run regressions
- git substrate projection regressions
- aggregate `dotctl check` regressions

## Not intentionally covered

- real package installation
- real yadm remote behavior
- generated Bashly parser behavior unless `TIER0_MODE=integration` is used with a projected `dotctl`
- app-specific config convergence
