#!/usr/bin/env bash
# Preview a website locally using the same build configuration as CI.
#
# Usage:
#   ./scripts/preview.sh <website> [port]
#   make preview WEBSITE=my-website
#
# Requires: go, python3 (pyyaml auto-installed on first run)
#
# The script reads websites-inventory/<website>.yaml to discover
# which repos to use, finds them as local checkouts, builds the site
# into a temp directory, and serves it on the given port.

set -euo pipefail

WEBSITE="${1:?Usage: $0 <website-name> [port]}"
PORT="${2:-8080}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "${SCRIPT_DIR}/../.." && pwd)"
_INVENTORY_DIR="${WEBSITES_INVENTORY_DIR:-${WORKSPACE}/websites-inventory}"
INVENTORY="${_INVENTORY_DIR}/${WEBSITE}.yaml"

if [[ ! -f "$INVENTORY" ]]; then
  echo "error: no inventory config found for '${WEBSITE}'" >&2
  echo "" >&2
  echo "Available websites:" >&2
  find "${_INVENTORY_DIR}/" -maxdepth 1 -name '*.yaml' -print0 2>/dev/null \
    | xargs -0 -n1 basename | sed 's/\.yaml$//' | sed 's/^/  /' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Parse a dot-path from the YAML config using Python + pyyaml.
# pyyaml is auto-installed if missing (only happens once, cached in pip).
# ---------------------------------------------------------------------------
yaml_get() {
  local key="$1"
  python3 - "${INVENTORY}" "${key}" <<'PY'
import sys

try:
    import yaml
except ImportError:
    import subprocess
    subprocess.run([sys.executable, "-m", "pip", "install", "pyyaml", "-q"], check=True)
    import yaml

d = yaml.safe_load(open(sys.argv[1]))
for key in sys.argv[2].split("."):
    d = (d or {}).get(key) if isinstance(d, dict) else None

print(d or "")
PY
}

# ---------------------------------------------------------------------------
# Find the local checkout directory for a GitHub "owner/repo" reference.
# Checks several common workspace layout conventions.
# ---------------------------------------------------------------------------
local_path() {
  local repo_full="$1"
  local name="${repo_full##*/}"   # strip "owner/" prefix

  # Standard nested convention used by most repos: workspace/name/name
  [[ -d "${WORKSPACE}/${name}/${name}" ]] && echo "${WORKSPACE}/${name}/${name}" && return
  # Tooling repos live under workspace/website/name
  [[ -d "${WORKSPACE}/website/${name}" ]] && echo "${WORKSPACE}/website/${name}" && return
  # Flat convention: workspace/name
  [[ -d "${WORKSPACE}/${name}" ]] && echo "${WORKSPACE}/${name}" && return

  echo ""
}

# ---------------------------------------------------------------------------
# Read inventory fields
# ---------------------------------------------------------------------------
WEBSITE_REPO="$(yaml_get "sources.website.repo")"
DATA_REPO="$(yaml_get "sources.data.repo")"
COMPILER_REPO="$(yaml_get "compiler.repo")"

WEBSITE_DIR="$(local_path "$WEBSITE_REPO")"
COMPILER_DIR="$(local_path "$COMPILER_REPO")"

if [[ -z "$COMPILER_DIR" ]]; then
  echo "error: compiler repo not found locally." >&2
  echo "  Expected: ${WORKSPACE}/website/$(basename "$COMPILER_REPO")/" >&2
  exit 1
fi
if [[ -z "$WEBSITE_DIR" ]]; then
  echo "error: website repo not found locally." >&2
  echo "  Expected: ${WORKSPACE}/$(basename "$WEBSITE_REPO")/$(basename "$WEBSITE_REPO")/" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Set up temp directories and cleanup handler
# ---------------------------------------------------------------------------
WORK_DIR="$(mktemp -d "/tmp/preview-src-${WEBSITE}-XXXXXX")"
OUT_DIR="$(mktemp -d "/tmp/preview-out-${WEBSITE}-XXXXXX")"
SERVER_PID=""

cleanup() {
  local pid="$SERVER_PID"
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
  fi
  rm -rf "$WORK_DIR" "$OUT_DIR"
  return 0
}
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Copy website to temp working directory so we never modify the source tree
# ---------------------------------------------------------------------------
cp -r "${WEBSITE_DIR}/." "${WORK_DIR}/"

# ---------------------------------------------------------------------------
# Inject data from the data repo (if configured)
# ---------------------------------------------------------------------------
if [[ -n "$DATA_REPO" ]]; then
  DATA_DIR="$(local_path "$DATA_REPO")"
  if [[ -z "$DATA_DIR" ]]; then
    echo "error: data repo not found locally." >&2
    echo "  Expected: ${WORKSPACE}/$(basename "$DATA_REPO")/$(basename "$DATA_REPO")/" >&2
    exit 1
  fi
  cp -r "${DATA_DIR}/site.d" "${WORK_DIR}/src/data/"
  cp    "${DATA_DIR}/site.yaml" "${WORK_DIR}/src/data/"
fi

# ---------------------------------------------------------------------------
# Print what we found
# ---------------------------------------------------------------------------
echo ""
printf "  %-12s %s\n" "compiler:"  "${COMPILER_DIR}"
printf "  %-12s %s\n" "website:"   "${WEBSITE_DIR}"
[[ -n "$DATA_REPO" ]] && printf "  %-12s %s\n" "data:"  "$(local_path "$DATA_REPO")"
echo ""

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
echo "  Building..."
go -C "${COMPILER_DIR}" run ./cmd/build-static \
  -website-root "${WORK_DIR}" \
  -out "${OUT_DIR}" \
  2>&1 | grep -E '"(starting|generated page|build completed)"' \
       | sed 's/.*msg="//;s/" .*//'

echo ""
echo "  http://localhost:${PORT}/"
echo "  Ctrl+C to stop."
echo ""

# ---------------------------------------------------------------------------
# Serve
# ---------------------------------------------------------------------------
python3 -m http.server "${PORT}" --directory "${OUT_DIR}"
