# floci-aws-demo

A production-shaped AWS platform described in Terraform, orchestrated by
Terragrunt across four layered stacks, and applied entirely on a laptop against
[floci](https://floci.io), a local AWS emulator. VPC, EKS, RDS, ElastiCache, ALB,
ECR, S3, KMS, Secrets Manager, SSM, **HashiCorp Vault** and **ArgoCD**.

No AWS account. No cloud spend. Four Node microservices actually serving traffic
through an emulated load balancer, deployed by GitOps.

![Architecture](docs/architecture.png)

## Why

Terraform's feedback loop against real AWS is punishing: an EKS cluster takes
~15 minutes to create and ~10 to destroy, so a typo in a security group rule
costs half an hour. Running the same configuration locally turns that into
seconds.

The catch is fidelity. An emulator that accepts your API calls but doesn't
behave like AWS gives false confidence. So this repo is also a record of **where
floci's fidelity ends**: see [docs/floci-gaps.md](docs/floci-gaps.md).

## Quickstart

Requires Docker Desktop, Terraform ≥ 1.10, Terragrunt ≥ 1.0, the AWS CLI and kubectl.

```bash
git clone https://github.com/elokac/floci-aws-demo.git
cd floci-aws-demo

docker compose up -d      # start floci
make up                   # apply 4 stacks -> build images -> deploy -> ALB -> frontend
```

Then exercise the whole chain:

```bash
ALB=$(./scripts/lib/outputs.sh alb_dns_name)

curl -s -X POST "http://$ALB/api/users" -H 'Content-Type: application/json' \
  -d '{"name":"ada","email":"ada@example.com"}'

curl -s -X POST "http://$ALB/api/orders" -H 'Content-Type: application/json' \
  -d '{"user_id":1,"item":"widget","amount_cents":4200}'
```

A `201` with `"status":"paid"` means every layer worked: ALB → gateway →
order-service → Postgres → payment-service → back.

![Application pods running on the emulated EKS cluster](docs/k8s-workloads.png)

Four services at two replicas each, scheduled by a real scheduler onto the k3s
node, pulling their images from the emulated ECR. The `Terminating` rows aged 11
days are not a hung deploy. They are pods left behind by an earlier floci, which
is [divergence 6](docs/floci-gaps.md#6-floci-discards-all-state-when-its-container-is-recreated).

`make help` lists everything else.

## The stacks

Four Terragrunt stacks, applied in dependency order. Each is one directory; the
directory name **is** the composite module name.

```
bootstrap ─→ iam ─→ stateful ─→ standard
```

| Stack | Contains | Why here |
|---|---|---|
| **bootstrap** | VPC, subnets, routing, security groups, KMS, ECR, S3, ACM, SSM | nothing exists without it |
| **iam** | cluster / node / app roles and policies | its own layer by convention |
| **stateful** | RDS, ElastiCache, Secrets Manager, Vault's KMS unseal key | data-bearing; slowest to rebuild |
| **standard** | EKS, ALB, CloudFront, Vault, ArgoCD, SSM | everything that needs the layers below |

Environments are **environment variables, not directories**. `ENVIRONMENT_NAME=staging make apply-all`
is the whole story, and state separates itself under `.state/<env>/<stack>/`.

Values cross stacks through a `resolved:` block folded into the YAML config by
each leaf `terragrunt.hcl`, so a composite module still takes exactly one
variable and never learns that four separate states exist.

## One config drives everything

[`terragrunt/aws/_env/config.yaml`](terragrunt/aws/_env/config.yaml) is the only
input. Composite modules take `variable "config" { type = string }` and
`yamldecode` it; nothing is passed as ordinary tfvars.

It is written to be **correct for real AWS**. A single switch,
`global.floci_compat`, is the entire local-emulator surface. It is honoured in
three places, each commented at the point of use.

## Layout

```
.
├── Makefile                    the interface: `make help`
├── terraform/                  ---- modules monorepo half ----
│   └── modules/
│       ├── composite-{bootstrap,iam,stateful,standard}/
│       ├── networking/  kms-key/  ecr-repository/  s3-buckets/  acm-certificate/
│       ├── iam-role/  rds/  elasticache/  secrets-manager/  ssm-parameters/
│       ├── eks-cluster/  alb/  cloudfront/
│       └── stateful-vault/  vault/  argocd/
├── terragrunt/                 ---- live repo half ----
│   └── aws/
│       ├── root.hcl            remote state + generated providers
│       ├── _env/               env.hcl (all get_env) + config.yaml
│       └── {bootstrap,iam,stateful,standard}/
├── services/                   4 Node services + the static frontend
├── k8s/                        GitOps source of truth; ArgoCD reconciles this
├── scripts/                    build, deploy, register targets, kubeconfig
└── verify.sh                   functional checks + drift detection
```

Each module follows one shape: `main.tf` / `variables.tf` / `versions.tf` /
`local.tf` / `outputs.tf`, plus `docs/header.md`. Every one takes `global_config`
and a single `<thing>_config` object, `for_each`es over a map built in locals,
and tags with `merge(var.global_config.tags, …)`.

## Vault and ArgoCD

**Vault** runs as a 3-replica Raft cluster, auto-unsealed by floci's **emulated
KMS**. The `awskms` seal calls `kms:Encrypt`/`Decrypt` from inside a pod on every
seal and unseal, so this is a real cryptographic round-trip through the emulator,
not a resource that merely gets created:

```
$ make vault-status
Seal Type       awskms
Initialized     true
Sealed          false
Storage Type    raft
```

![Three Vault pods on the emulated EKS cluster](docs/k8s-vault.png)

The root token never enters Terraform state. Terraform creates an *empty*
Secrets Manager container; `vault-init.sh` runs `operator init` and writes the
value with `put-secret-value`, passing it via `file://` so it never appears in
`ps` output either. `make vault-token` retrieves it.

**ArgoCD** reconciles [`k8s/`](k8s/) from this repository:

```
$ make argocd-sync
NAME     SYNC     HEALTH    REVISION
msdemo   Synced   Healthy   3247b464…
```

![The argocd namespace on the emulated EKS cluster](docs/k8s-argocd.png)

That is why the manifests carry **real, committed image references** rather than
a `PLACEHOLDER` patched in by `kubectl set image`. GitOps and imperative patching
do not mix: Argo reverts the patch on its next sync.

## Verification

`verify.sh` does **round-trips, not `describe-*` calls**. An emulator's control
plane will happily report a resource healthy with nothing behind it.

- **KMS**: encrypt a string, decrypt it, assert the bytes match
- **S3**: put an object, get it, `cmp` against the original
- **Secrets Manager**: fetch, parse, name any missing keys
- **RDS**: resolve the endpoint, TCP-probe it, run `select version()`
- **ALB**: describe listeners, count healthy targets, drive real traffic

It also detects **orphans** (live in floci, absent from state, which is what a
crashed provider leaves behind) and **stale state** (floci restarted; state
survived).

## What floci actually is

The thing that predicts nearly every behaviour: floci emulates the AWS **control
plane** and delegates the **data plane** to real containers.

```
floci-eks-msdemo-cluster   rancher/k3s      a genuine Kubernetes API
floci-rds-db-…             postgres:16      a genuine database
floci-ecr-registry         registry:2       a genuine OCI registry
```

Where a container backs the service, fidelity is excellent. Where none does, you
get a control-plane object that records your intent and does nothing.
ElastiCache and CloudFront are the two that bite.

![AWS resources](docs/aws-resources.png)

- [docs/aws-resources.md](docs/aws-resources.md): every resource created, and
  how each behaves compared with real AWS
- [docs/floci-gaps.md](docs/floci-gaps.md): the seven places floci diverges from
  real AWS, and which of them are dangerous

## Caveats

- **floci keeps no state across restarts.** Recreating the container discards
  everything while `.state/` survives on disk. `verify.sh` detects this. It also
  orphans the previous k3s node, leaving pods stuck `Terminating`.
- **`:latest` is a mutable tag**, so a rebuilt image doesn't change the manifest
  and nothing restarts. `deploy.sh` issues an explicit `rollout restart`; the
  correct fix is immutable `:git-sha` tags.
- **The demo DB password lives in `env.hcl`** for zero-setup cloning. A `check`
  block refuses it whenever the endpoint isn't local.

## Licence

MIT.
