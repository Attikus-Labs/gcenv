#!/usr/bin/env bash
# Sync the plugin manifest version to package.json's version.
#
# package.json is the single source of truth (Changesets bumps it). The Claude
# Code plugin manifest carries its own "version" field that the marketplace UI
# reads, so it has to be kept in lockstep. Run this after `changeset version`.
#
# Idempotent: a no-op if the versions already match. Prints what it did.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pkg="$repo_root/package.json"
manifest="$repo_root/plugins/gcenv/.claude-plugin/plugin.json"

for f in "$pkg" "$manifest"; do
  [[ -f "$f" ]] || { echo "sync-plugin-version: missing $f" >&2; exit 1; }
done

version="$(jq -r '.version' "$pkg")"
if [[ -z "$version" || "$version" == "null" ]]; then
  echo "sync-plugin-version: no version in $pkg" >&2
  exit 1
fi

current="$(jq -r '.version' "$manifest")"
if [[ "$current" == "$version" ]]; then
  echo "plugin.json already at $version — no change."
  exit 0
fi

tmp="$(mktemp)"
jq --arg v "$version" '.version = $v' "$manifest" > "$tmp"
mv "$tmp" "$manifest"
echo "plugin.json version: $current -> $version"
