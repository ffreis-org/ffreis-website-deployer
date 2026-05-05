# website-deployer

Centralized deployment authority for all websites in the fleet.

One workflow per website. Deploy mode (`auto` / `manual`) is controlled by the
`deploy_mode` field in your `websites-inventory` repo.

## How it works

```
source repo push
      │
      ▼
repository_dispatch ──► deploy-{website}.yml
                              │
                    ┌─────────▼──────────┐
                    │  config job         │  reads websites-inventory YAML
                    │  gate on deploy_mode│  skip if manual + not workflow_dispatch
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │  validate job       │  inject data, validate-site-data
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │  build job          │  build-static, upload to staging bucket
                    └─────────┬──────────┘
                              │
                    ┌─────────▼──────────┐
                    │  promote job        │  sync staging → live, CF invalidation
                    └─────────────────────┘
```

## Secrets (on the `prod` environment)

| Secret | Description |
|---|---|
| `AWS_DEPLOY_ROLE_ARN` | OIDC role ARN with S3 + CloudFront permissions |
| `CF_DISTRIBUTION_ID` | CloudFront distribution ID |
| `S3_WEBSITE_BUCKET` | Live website S3 bucket name |
| `CI_REPO_READ_TOKEN` | Token to check out private source repos |

## Variables (repository level)

| Variable | Description |
|---|---|
| `INVENTORY_REPO` | Override for websites-inventory repo (default: `{owner}/websites-inventory`) |

## Adding a new website

1. Add `{website}.yaml` to websites-inventory with `deploy_mode: manual`
2. Copy an existing `.github/workflows/deploy-{existing}.yml` to `deploy-{website}.yml`
3. Replace the existing website name with the new website name in the workflow
4. Add required secrets to the `prod` environment
5. Trigger a `workflow_dispatch` to verify end-to-end
6. Set `deploy_mode: auto` in websites-inventory once verified

## Manual promotion / rollback

Use `workflow_dispatch` on the relevant workflow and optionally provide
`website_sha` and/or `data_sha` to pin specific source commits.
