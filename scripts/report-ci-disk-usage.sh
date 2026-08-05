#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/report-ci-disk-usage.sh LABEL

Print a compact disk-usage report for CI reference blueprint jobs.

The BP_REFERENCE_SOURCE_IDENTITY, BP_REFERENCE_DEPENDENCY_PACKAGES_PATH,
BP_REFERENCE_DEPENDENCY_PATH_BUILDS_PATH, and BP_REFERENCE_ARTIFACT_PATH
environment variables select the per-reference paths to include.
EOF
}

reference_source_identity="${BP_REFERENCE_SOURCE_IDENTITY:-}"
reference_dependency_packages_path="${BP_REFERENCE_DEPENDENCY_PACKAGES_PATH:-}"
reference_dependency_path_builds_path="${BP_REFERENCE_DEPENDENCY_PATH_BUILDS_PATH:-}"
artifact_path="${BP_REFERENCE_ARTIFACT_PATH:-}"

if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
  usage
  exit 0
fi
if [[ $# -ne 1 ]]; then
  usage >&2
  exit 2
fi
label="$1"

begin_group() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    printf '::group::%s\n' "$1"
  else
    printf '## %s\n' "$1"
  fi
}

end_group() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    printf '::endgroup::\n'
  fi
}

report_df() {
  local paths=(".")
  if [[ -n "${RUNNER_TEMP:-}" ]]; then
    paths+=("$RUNNER_TEMP")
  fi
  if [[ -n "${HOME:-}" ]]; then
    paths+=("$HOME")
  fi
  paths+=("/tmp")

  printf '[ci-disk] filesystems\n'
  df -h "${paths[@]}" | awk '!seen[$0]++'
}

report_du() {
  local path
  local paths=(
    ".lake"
    ".lake/packages"
    ".lake/build"
    ".lake/packages/mathlib"
    ".lake/packages/mathlib/.lake/build"
    ".lake/packages/verso"
    ".lake/packages/verso/.lake/build"
    ".worktrees/_reference-blueprints"
    ".worktrees/_reference-blueprints/cache"
    ".worktrees/_reference-blueprints/deps"
    ".worktrees/_reference-blueprints/by-worktree"
    "_out"
    "_out/reference-blueprints"
  )

  if [[ -n "$reference_source_identity" ]]; then
    paths+=(
      ".worktrees/_reference-blueprints/cache/$reference_source_identity"
    )

    shopt -s nullglob
    local local_checkouts=(.worktrees/_reference-blueprints/by-worktree/*/"$reference_source_identity")
    shopt -u nullglob
    paths+=("${local_checkouts[@]}")
  fi

  if [[ -n "$reference_dependency_packages_path" ]]; then
    paths+=("$reference_dependency_packages_path")
  fi
  if [[ -n "$reference_dependency_path_builds_path" ]]; then
    paths+=("$reference_dependency_path_builds_path")
  fi

  if [[ -n "$artifact_path" ]]; then
    paths+=("$artifact_path")
  fi

  printf '[ci-disk] selected paths\n'
  for path in "${paths[@]}"; do
    if [[ -e "$path" || -L "$path" ]]; then
      du -sh "$path"
    else
      printf 'missing\t%s\n' "$path"
    fi
  done
}

report_reference_children() {
  local root=".worktrees/_reference-blueprints"
  if [[ -d "$root" ]]; then
    printf '[ci-disk] reference cache children\n'
    du -sh "$root"/* 2>/dev/null | sort -h || true
  fi

  if [[ -n "$reference_dependency_packages_path" ]]; then
    if [[ -d "$reference_dependency_packages_path" ]]; then
      printf '[ci-disk] packages for %s\n' "$reference_source_identity"
      du -sh "$reference_dependency_packages_path"/* 2>/dev/null | sort -h || true
    fi
  fi
  if [[ -n "$reference_dependency_path_builds_path" ]]; then
    if [[ -d "$reference_dependency_path_builds_path" ]]; then
      printf '[ci-disk] path builds for %s\n' "$reference_source_identity"
      du -sh "$reference_dependency_path_builds_path"/* 2>/dev/null | sort -h || true
    fi
  fi
}

begin_group "Disk usage: $label"
printf '[ci-disk] label=%s\n' "$label"
if [[ -n "$reference_source_identity" ]]; then
  printf '[ci-disk] reference_source_identity=%s\n' "$reference_source_identity"
fi
if [[ -n "$reference_dependency_packages_path" ]]; then
  printf '[ci-disk] reference_dependency_packages_path=%s\n' "$reference_dependency_packages_path"
fi
if [[ -n "$reference_dependency_path_builds_path" ]]; then
  printf '[ci-disk] reference_dependency_path_builds_path=%s\n' "$reference_dependency_path_builds_path"
fi
if [[ -n "$artifact_path" ]]; then
  printf '[ci-disk] artifact_path=%s\n' "$artifact_path"
fi
report_df
report_du
report_reference_children
end_group
