#!/usr/bin/env bash
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(CDPATH= cd -- "$script_dir/../.." && pwd -P)"
out_dir="${1:-$repo_root/dist}"
name="tier0-robustness-tests"
root="$(mktemp -d)"
archive_root="$root/$name"

mkdir -p "$archive_root"

for rel in \
  README.md \
  CRAWL.md \
  manifest.json \
  Justfile.tier0-snippet \
  tests
do
  if [[ -e "$repo_root/tier-0/$rel" || -L "$repo_root/tier-0/$rel" ]]; then
    cp -a -- "$repo_root/tier-0/$rel" "$archive_root/$rel"
  fi
done

mkdir -p "$out_dir"
out_dir="$(CDPATH= cd -- "$out_dir" && pwd -P)"
tar -C "$root" -czf "$out_dir/$name.tar.gz" "$name"
(cd "$root" && zip -qr "$out_dir/$name.zip" "$name")

printf '%s\n' "$out_dir/$name.tar.gz"
printf '%s\n' "$out_dir/$name.zip"
