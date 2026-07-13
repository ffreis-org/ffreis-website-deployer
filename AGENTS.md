# Agent Context

**This repo:** `ffreis-website-deployer` — GitHub Actions workflows that orchestrate
CI/CD for the entire website fleet. The central `deploy.yml` reads from the inventory
repo to build and promote any managed website. The `local/` directory contains the
docker-compose watch stack used by `ffreis-siteops` for local development.

For the complete system map — how this repo relates to siteops, the compiler,
the inventory, S3 infrastructure, and the individual websites — see the private
fleet inventory repository:

> the fleet inventory (private repo — do not name it in commits or PR descriptions)

Architecture detail (CI/CD job graph, design decisions): `AGENTS.md` links to
`docs/ARCHITECTURE.md` in the same repo.

Do not look for cross-component flow documentation in this repo's README;
it covers only the deployer's own workflows and local runtime.

## Branching Model and Environment Separation

### Core rule

The `website_name` input to `deploy.yml` is the sole join point between a source-repo push and the AWS resources it touches. It determines which inventory YAML is read, which GitHub environment resolves secrets, which S3 bucket receives the build, and which CloudFront distribution is invalidated.

```
push to develop  →  website_name = <site>-dev  →  <site>-dev.yaml  →  github_environment: <site>-dev  →  dev AWS resources
push to main     →  website_name = <site>       →  <site>.yaml       →  github_environment: prod          →  prod AWS resources
```

### GitHub environments on this repo

| GitHub environment | Site | AWS resources |
|---|---|---|
| `prod` | flemming | `flemming-*-prod`, `flemming.com.br` |
| `flemming-dev` | flemming-dev | `flemming-*-dev`, `<dev-domain>` |
| `petlook-prod` | petlook | `petlook-*-prod`, `petlook.app` |
| `petlook-dev` | petlook-dev | `petlook-*-dev`, `<dev-domain>` |
| `ffreis-prod` | ffreis | `ffreis-*-prod`, `ffreis.com` |
| `ffreis-dev` | ffreis-dev | `ffreis-*-dev`, `<dev-domain>` |

Each environment holds independent secrets: `AWS_DEPLOY_ROLE_ARN`, `CF_DISTRIBUTION_ID`, `S3_WEBSITE_BUCKET`.

### Why a PR into `develop` cannot deploy to production

1. Deploy jobs in source repos fire only on `push` events, not `pull_request`.
2. Push to `develop` → dispatch fires `website_name=<site>-dev`.
3. `<site>-dev.yaml` declares `github_environment: <site>-dev`.
4. `<site>-dev` holds the dev OIDC role ARN, which has IAM permissions only on dev S3/CloudFront.
5. No path from step 2 touches prod resources.

### Why a PR into `main` cannot use dev config

1. A PR into `main` only runs validation CI — no dispatch step fires.
2. Once merged: push to `main` → dispatch fires `website_name=<site>`.
3. `<site>.yaml` declares the prod GitHub environment. Dev inventory files are never read.

### Adding a new site environment

1. Create `<site>-dev.yaml` in the fleet inventory with `github_environment: <site>-dev`.
2. Create the `<site>-dev` GitHub environment on this repo. Add secrets from dev Terraform outputs.
3. Update source repo CI to dispatch `<site>-dev` on develop, `<site>` on main.
4. Validate with `workflow_dispatch` → `website_name=<site>-dev` before setting `deploy_mode: auto`.

### watch.yml and dev sites

`watch.yml` dispatches all inventory files with at least one `deploy_mode: auto` deployment, including dev files. Dev environments with `auto` deployments are kept fresh automatically alongside prod.

## Public repo — private-repo hygiene

This is a **public** GitHub repository. When writing commit messages, PR titles,
PR descriptions, or any other user-visible text, **never name private repos** —
website content, inventory, infra, Lambda, or data repos that are not publicly
listed. Use generic terms instead: "the fleet inventory", "a private consumer",
"internal infra", "private data repo", etc.

## Content source selection

Each inventory YAML may carry a top-level `content_source` field (default: `prod`):

```yaml
content_source: mock   # "prod" (default) or "mock"
```

When `content_source: mock`, the `config` job validates the field is only used on
dev environments (`github_environment` ending in `-dev`) — any other combination is
a fatal error. The build step then swaps the content paths to `mock/` subdirectories:
- posts: `checkout/posts/mock/posts/`
- projects: `checkout/projects/mock/projects.yaml`
- courses: `checkout/courses/mock/courses.yaml`

It also passes `-content-source mock` to the compiler, which enforces the anti-leak
guard at build time: the compiler rejects any `/mock/` path when not in mock mode.

## Compiler embedding flags in inventory YAML

The `compiler` section of each inventory YAML can carry optional fields that control
how the compiler embeds resources into HTML during CI builds:

```yaml
compiler:
  repo: ...
  ref: main
  js_inline_threshold: 32768        # optional; compiler default = 8192 (8 KB); 0 = disable
  js_shared_inline_threshold: 8192  # optional; scripts on >1 page use this lower limit; -1 = off
  raster_inline_threshold: 2147483647  # optional; compiler default = 0 (disabled); large = all
  embed_fonts: false                # optional; default false
  inline_body_css: false            # optional; default false
```

These fields are site-level (not per-deployment). The `deploy.yml` config job
extracts them from `top_compiler` and passes them as matrix outputs:
`compiler_js_inline_threshold`, `compiler_js_shared_inline_threshold`,
`compiler_raster_inline_threshold`, `compiler_embed_fonts`, `compiler_inline_body_css`.
The build step converts them into the matching compiler flags.

## Local deploy (`local/deploy-local.sh`) — the sanctioned local-first path

When GitHub Actions is unavailable (e.g. the billing pause), deploy with
`local/deploy-local.sh <website_name>` instead of an ad-hoc `aws s3 sync`. It is a
faithful replica of `deploy.yml`'s build → promote → invalidate: it resolves the
inventory YAML with the **same** `resolve()` logic, exports each source repo at its
pinned ref, injects data/shared-JS, and — critically — passes
`-posts-dir`/`-projects-file`/`-courses-file` exactly like CI.

**Why it exists:** a manual `aws s3 sync` of a local build skips the content
injection, so the compiler renders the `60-pages.yaml` blog **seed** placeholder
(`/blog/production-ml-systems/`, which 404s) instead of the real posts. That is
exactly how the mock post reached ffreis.com prod on 2026-06-29. This script closes
that gap and refuses to publish a build whose blog listing links a card with no
backing post page (the seed-leak signature).

```bash
local/deploy-local.sh ffreis                       # build + guard only (no AWS) — DEFAULT
CF_DISTRIBUTION_ID=<id> local/deploy-local.sh ffreis --deploy --yes-prod   # publish prod
```

- Default action is `--build-only` (no AWS calls). `--deploy` syncs to the live
  bucket + invalidates CloudFront; a prod target additionally requires `--yes-prod`.
- Sync mirrors CI: `--delete` is skipped when sibling deployments share the bucket
  (e.g. ffreis `en`/`pt`), so one language never wipes another's content.
- Run from a normal checkout, or pass `--workspace <root>` / `--inventory <dir>`
  when running from a git worktree.
- This is a `-content-source prod` build; it does not enable the `mock/` content
  system (see "Content source selection"). The two guards are independent.

## Keeping this file current

- **If you discover a fact not reflected here:** add it before finishing your task.
- **If something here is wrong or outdated:** correct it in the same commit as the code change.
- **If you rename a file, command, or concept referenced here:** update the reference.
