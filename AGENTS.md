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

## Public repo — private-repo hygiene

This is a **public** GitHub repository. When writing commit messages, PR titles,
PR descriptions, or any other user-visible text, **never name private repos** —
website content, inventory, infra, Lambda, or data repos that are not publicly
listed. Use generic terms instead: "the fleet inventory", "a private consumer",
"internal infra", "private data repo", etc.

## Keeping this file current

- **If you discover a fact not reflected here:** add it before finishing your task.
- **If something here is wrong or outdated:** correct it in the same commit as the code change.
- **If you rename a file, command, or concept referenced here:** update the reference.
