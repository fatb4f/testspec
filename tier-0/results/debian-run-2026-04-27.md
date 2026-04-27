# Tier-0 Debian Run

Date: 2026-04-27

Execution target:
- container: `tier0-debian`
- image: `debian:trixie`
- runtime: rootless Docker via `distrobox`

Command run:

```sh
docker exec -u root 976acb2b55e8 bash --noprofile --norc -lc '
  . /home/x404/.config/shell/load-env.sh
  cd /home/x404/.local/share/testspec
  bash ./tier-0/tests/tier0/run.sh --all --repo /home/x404
'
```

Observed pass sequence:

1. `clean_bash_load`
2. `clean_zsh_load`
3. `login_zsh_no_hang`
4. `bash_to_zsh`
5. `zsh_to_bash`
6. `path_resolution`

Observed failure:

- `precommit_lint`

Failure details:

```txt
error: Recipe `precommit-lint` failed on line 25 with exit code 1
phases.6.ok: conflicting values true and false
summary.ok: conflicting values true and false
summary.count: invalid value 7 (out of bound >=12)
```

Result:

- Debian distrobox path is functional.
- The archive harness stops at the precommit lint gate in this environment.
- Arch image has not been run yet.
