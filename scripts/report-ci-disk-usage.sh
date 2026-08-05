#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/report-ci-disk-usage.sh LABEL [options]

Print a compact disk-usage report for CI reference blueprint jobs.

Options:
  --reference-source-identity ID
                              Include per-reference paths for the source ID.
  --artifact-path PATH        Include the generated artifact path.
  -h, --help                  Show this help.
EOF
}

label=""
reference_source_identity=""
artifact_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --reference-source-identity)
      if [[ $# -lt 2 ]]; then
        echo "missing value for --reference-source-identity" >&2
        exit 2
      fi
      reference_source_identity="$2"
      shift 2
      ;;
    --artifact-path)
      if [[ $# -lt 2 ]]; then
        echo "missing value for --artifact-path" >&2
        exit 2
      fi
      artifact_path="$2"
      shift 2
      ;;
    -*)
      echo "unknown option: $1" >&2
      exit 2
      ;;
    *)
      if [[ -n "$label" ]]; then
        echo "unexpected argument: $1" >&2
        exit 2
      fi
      label="$1"
      shift
      ;;
  esac
done

if [[ -z "$label" ]]; then
  usage >&2
  exit 2
fi

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
      ".worktrees/_reference-blueprints/deps/$reference_source_identity"
      ".worktrees/_reference-blueprints/deps/$reference_source_identity/packages"
      ".worktrees/_reference-blueprints/deps/$reference_source_identity/path-builds"
    )

    shopt -s nullglob
    local local_checkouts=(.worktrees/_reference-blueprints/by-worktree/*/"$reference_source_identity")
    shopt -u nullglob
    paths+=("${local_checkouts[@]}")
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

  if [[ -n "$reference_source_identity" ]]; then
    local packages=".worktrees/_reference-blueprints/deps/$reference_source_identity/packages"
    if [[ -d "$packages" ]]; then
      printf '[ci-disk] packages for %s\n' "$reference_source_identity"
      du -sh "$packages"/* 2>/dev/null | sort -h || true
    fi
    local path_builds=".worktrees/_reference-blueprints/deps/$reference_source_identity/path-builds"
    if [[ -d "$path_builds" ]]; then
      printf '[ci-disk] path builds for %s\n' "$reference_source_identity"
      du -sh "$path_builds"/* 2>/dev/null | sort -h || true
    fi
  fi
}

begin_group "Disk usage: $label"
printf '[ci-disk] label=%s\n' "$label"
if [[ -n "$reference_source_identity" ]]; then
  printf '[ci-disk] reference_source_identity=%s\n' "$reference_source_identity"
fi
if [[ -n "$artifact_path" ]]; then
  printf '[ci-disk] artifact_path=%s\n' "$artifact_path"
fi
report_df
report_du
report_reference_children
end_group
