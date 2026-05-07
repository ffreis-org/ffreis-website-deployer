#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${ROOT_DIR:-/workspace}"
WEBSITE_ROOT="${WEBSITE_ROOT:-}"
OUT_DIR="${OUT_DIR:-}"
SITE_DATA_SOURCE="${SITE_DATA_SOURCE:-}"
SITE_DATA_SHARED="${SITE_DATA_SHARED:-}"
INLINE_ASSETS="${INLINE_ASSETS:-false}"
COPY_ASSETS="${COPY_ASSETS:-true}"
ENABLE_SANITY="${ENABLE_SANITY:-false}"
STRICT_CONTRACT="${STRICT_CONTRACT:-false}"
WEBSITE_COMPILER_BIN="${WEBSITE_COMPILER_BIN:-/usr/local/bin/website-compiler}"
COMPILER_WATCH_PATH="${COMPILER_WATCH_PATH:-.}"


[[ -n "${WEBSITE_ROOT}" ]] || { echo "WEBSITE_ROOT is required"; exit 1; }
[[ -n "${OUT_DIR}" ]] || { echo "OUT_DIR is required"; exit 1; }
[[ -x "${WEBSITE_COMPILER_BIN}" ]] || { echo "WEBSITE_COMPILER_BIN is not executable: ${WEBSITE_COMPILER_BIN}"; exit 1; }

cd "${ROOT_DIR}"
[[ -d "${COMPILER_WATCH_PATH}" ]] || { echo "COMPILER_WATCH_PATH is not a directory: ${COMPILER_WATCH_PATH}"; exit 1; }

# inject_data mirrors what CI does: copy data from the external data repo into
# the website's src/data/ directory so the compiler can read it from the default path.
inject_data() {
  local data_dir="${WEBSITE_ROOT}/src/data"
  mkdir -p "${data_dir}/site.d"

  if [[ -n "${SITE_DATA_SOURCE}" && -d "${SITE_DATA_SOURCE}" ]]; then
    [[ -f "${SITE_DATA_SOURCE}/site.yaml" ]] \
      && cp "${SITE_DATA_SOURCE}/site.yaml" "${data_dir}/site.yaml"
    if [[ -d "${SITE_DATA_SOURCE}/site.d" ]]; then
      find "${SITE_DATA_SOURCE}/site.d" -maxdepth 1 -name "*.yaml" \
        -exec cp {} "${data_dir}/site.d/" \;
    fi
  fi

  if [[ -n "${SITE_DATA_SHARED}" && -d "${SITE_DATA_SHARED}" ]]; then
    find "${SITE_DATA_SHARED}" -maxdepth 1 -name "*.yaml" \
      -exec cp {} "${data_dir}/site.d/" \;
  fi
}

build_site() {
  echo "[$(date -Iseconds)] Injecting data and building site..."
  inject_data
  "${WEBSITE_COMPILER_BIN}" build \
    -website-root "${WEBSITE_ROOT}" \
    -out "${OUT_DIR}" \
    -inline-assets="${INLINE_ASSETS}" \
    -copy-assets="${COPY_ASSETS}" \
    -sanity="${ENABLE_SANITY}" \
    -strict-contract="${STRICT_CONTRACT}"
  echo "[$(date -Iseconds)] Build complete."
  return 0
}

watch_loop() {
  inotifywait -r -e modify,create,delete,move \
    --exclude '(^|/)(\.git|dist|node_modules|\.venv)(/|$)' \
    "${WEBSITE_ROOT}" "${COMPILER_WATCH_PATH}"
  return 0
}

build_site

echo "Watching for changes in ${WEBSITE_ROOT} and ${COMPILER_WATCH_PATH} ..."
while watch_loop; do
  build_site || echo "[$(date -Iseconds)] Build failed; waiting for next change..."
done
