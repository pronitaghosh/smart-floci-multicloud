# Changelog

## [4f5f780] - 2026-09-22 22:05:48 UTC - refactor: rename project identifier msdemo -> smartcloud
- **Commit:** `4f5f780697a285f3151354dce5c2d09eaf594479` (`4f5f780`)
- **Date:** 2026-09-22 22:05:48 UTC (2026-09-22 15:05:48 PDT)
- **Agent:** Muse Spark (opencode/muse-spark-1.2-contributor-free)
- **Model:** muse-spark-1.2-contributor-free
- **Version:** 1.2
- **Working directory:** `/home/smartass/projects/multi-cloud-local/demo-floci-multicloud`
- **Git base:** `c2bb6b2` `chore: update the documentation` -> `4f5f780` `refactor: rename project identifier msdemo -> smartcloud`

### Changed - Project rename `msdemo` -> `smartcloud`

#### Source of truth (20 files, 94 occurrences)
- `terragrunt/aws/_env/config.yaml:9` `client_name: msdemo -> smartcloud`
- `terragrunt/aws/_env/config.yaml:30` `tags.Project`, `42` `network.name`, `80` `bucket msdemo-frontend-static -> smartcloud-frontend-static`
- `terragrunt/aws/_env/config.yaml:87` `domain_name msdemo.local -> smartcloud.local` (aliases, CloudFront comment)
- `terragrunt/aws/_env/config.yaml:94,99,106,109` `iam_roles` (`msdemo-cluster-* -> smartcloud-cluster-*`)
- `terragrunt/aws/_env/config.yaml:125-126` `db_name msdemo -> smartcloud`, `username msdemo_admin -> smartcloud_admin`
- `terragrunt/aws/_env/config.yaml:146,154,161,171,173,175-176,183,187,198-199,203-204,217,241,245` (`vault_static`, `secrets`, `clusters`, `load_balancers`, `cloudfront_distributions`, `vault`, `argocd destination_namespace`, `admin_password_secret_name`)
- `terragrunt/aws/_env/env.hcl:13` `CLIENT_NAME default msdemo -> smartcloud`
- `terragrunt/aws/standard/terragrunt.hcl:48,62-63,77-79` `mock_outputs` (`vpc-mock`, `role_arns`, `vault_*`)
- `k8s/00-namespace.yaml:4`, `k8s/10-gateway.yaml:5,18,24,39`, `k8s/11-user-service.yaml:5,18,24,26,41`, `k8s/12-order-service.yaml:5,18,24,26,41`, `k8s/13-payment-service.yaml:5,18,36`, `k8s/kustomization.yaml:23,35,37,39,41` (`namespace msdemo -> smartcloud`, `msdemo-config -> smartcloud-config`, `msdemo-db-secret -> smartcloud-db-secret`, `ecr 5100/msdemo/* -> 5100/smartcloud/*`, `*.msdemo.svc.cluster.local -> *.smartcloud.svc.cluster.local`)
- `scripts/render-k8s-config.sh:82-83,89-91,108-109` (ConfigMap/Secret names, `USER_SERVICE_URL` etc.)
- `scripts/deploy.sh:51-52,71,75,78`, `scripts/register-alb-targets.sh:21,27,32,37`, `scripts/fix-kubeconfig.sh:27`
- `verify.sh:17` `PROJECT=msdemo -> smartcloud`
- `Makefile:13,124-125,145,154,159,165` (`CLIENT_NAME?=smartcloud`, `kubectl -n smartcloud`, `smartcloud-vault-root-token`, `smartcloud/argocd-admin`)
- `terraform/modules/argocd/variables.tf:34` `destination_namespace msdemo -> smartcloud`
- `terraform/modules/vault/scripts/vault-init.sh:16` comment `msdemo-vault-0 -> smartcloud-vault-0`
- `scripts/gen-aws-resources.py:111,226` (`/msdemo/* -> /smartcloud/*`)
- `services/frontend/index.html:38` (`/msdemo/gateway_url -> /smartcloud/gateway_url`)

#### Generated / ignored (cleaned, will regenerate)
- Removed `k8s/01-config.yaml`, `.outputs.json`, `build-images.txt`, `dist/` (gitignored, produced by `scripts/render-k8s-config.sh:76` and `scripts/lib/outputs.sh`)
- Ran `terraform fmt -recursive terraform/` and `terragrunt hcl format --working-dir terragrunt/aws`

#### State handling required
- `.state/dev/*/terraform.tfstate` still contains 222 `msdemo` resources (`bootstrap/iam/stateful/standard`). New names are disjoint; next `make apply-all` will create `smartcloud-*` alongside orphans.
- Action before `make up`: `make down` or `rm -rf .state/dev .terragrunt-cache` then `docker compose down -v && docker compose up -d` then `CLIENT_NAME=smartcloud make up`. Old namespace `msdemo` will remain until `kubectl delete ns msdemo`.

#### Not changed (historical/docs)
- `README.md`, `docs/aws-resources.svg`, `docs/floci-gaps.md`, `docs/medium-article.md`, `Troubleshoot.md`, `K8-commands.md` still reference `floci-eks-msdemo-cluster` and example outputs.

#### Validation
- `grep -rn msdemo --exclude-dir=.git --exclude-dir=.terragrunt-cache --exclude-dir=.terraform --exclude-dir=.state` shows 0 hits in functional code; remaining 144 hits are docs/logs/.state only.
- Working tree status: 20 files modified (see `git diff --stat`).
