#!/usr/bin/env bash
set -euo pipefail

PREFIX="${PREFIX:-}"
IMAGE_PROVIDER="${IMAGE_PROVIDER:-}"
IMAGE_TAG="${IMAGE_TAG:-local}"
IMAGE_PREFIX="${IMAGE_PREFIX:-}"
COMPILER_IMAGE_NAME="${COMPILER_IMAGE_NAME:-website-compiler-cli}"
COMPILER_WATCH_IMAGE_NAME="${COMPILER_WATCH_IMAGE_NAME:-website-compiler-watch}"

if [[ -z "${IMAGE_PREFIX}" ]]; then
  if [[ -n "${IMAGE_PROVIDER}" ]]; then
    IMAGE_PREFIX="${IMAGE_PROVIDER}/${PREFIX}"
  else
    IMAGE_PREFIX="${PREFIX}"
  fi
fi

IMAGE_ROOT="${IMAGE_ROOT:-${IMAGE_PREFIX}}"
WEBSITE_COMPILER_IMAGE="${WEBSITE_COMPILER_IMAGE:-${IMAGE_ROOT}/${COMPILER_IMAGE_NAME}:${IMAGE_TAG}}"
COMPILER_WATCH_IMAGE="${COMPILER_WATCH_IMAGE:-${IMAGE_ROOT}/${COMPILER_WATCH_IMAGE_NAME}:${IMAGE_TAG}}"
COMPILER_WATCH_RUNTIME_IMAGE="${COMPILER_WATCH_RUNTIME_IMAGE:-debian:bookworm-slim}"
PREVIEW_IMAGE="${PREVIEW_IMAGE:-nginx:alpine}"

export PREFIX IMAGE_PROVIDER IMAGE_TAG COMPILER_IMAGE_NAME COMPILER_WATCH_IMAGE_NAME IMAGE_PREFIX IMAGE_ROOT WEBSITE_COMPILER_IMAGE COMPILER_WATCH_IMAGE COMPILER_WATCH_RUNTIME_IMAGE PREVIEW_IMAGE

if [[ -n "${COMPOSE_COMMAND:-}" ]]; then
  exec ${COMPOSE_COMMAND} "$@"
fi


if command -v podman >/dev/null 2>&1 && podman compose version >/dev/null 2>&1; then
  exec podman compose "$@"
fi

if command -v podman-compose >/dev/null 2>&1; then
  exec podman-compose "$@"
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  exec docker compose "$@"
fi

echo "No usable compose command found. Set COMPOSE_COMMAND or install docker compose / podman compose / podman-compose." >&2
exit 1
