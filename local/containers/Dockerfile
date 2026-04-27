ARG WEBSITE_COMPILER_IMAGE
ARG STITCHER_RUNTIME_IMAGE=debian:bookworm-slim
FROM ${WEBSITE_COMPILER_IMAGE} AS compiler_cli

FROM ${STITCHER_RUNTIME_IMAGE}

RUN apt-get update \
  && apt-get install -y --no-install-recommends bash ca-certificates inotify-tools \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

COPY --from=compiler_cli /usr/local/bin/website-compiler /usr/local/bin/website-compiler

CMD ["bash", "./scripts/watch-build.sh"]
