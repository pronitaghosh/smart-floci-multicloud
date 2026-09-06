# I Built a Production-Shaped AWS Platform on My Laptop. Here's Exactly How I did it.

## 67 Terraform resources, Vault, ArgoCD and a Kubernetes cluster, with no AWS account. And the seven places it stopped behaving like AWS.

---

An EKS cluster takes about 15 to 20 minutes to create on real AWS and 10 to
destroy. Get a security group rule wrong and you have spent half an hour finding
out. Multiply that by the number of times you actually iterate on a module and
the arithmetic gets depressing. Which is why most of us batch Terraform changes
and apply them in nervous clumps, rather than the way we'd write any other code.

So I tried running the whole thing locally. Not a subset, not mocks: a
production-shaped platform, laid out the way a real infrastructure repo is laid
out.

- **Terragrunt across four layered stacks**: `bootstrap → iam → stateful → standard`
- **67 AWS resources**: VPC, EKS, RDS, ElastiCache, ALB, ECR, S3, KMS, ACM,
  Secrets Manager, SSM, IAM
- **HashiCorp Vault** in HA, auto-unsealed by the emulated KMS
- **ArgoCD** reconciling workloads from git
- one YAML config as the only input, the way composite modules usually work

All of it against [floci](https://floci.io), an AWS emulator that runs in
Docker. No account, no spend, apply in seconds.

It worked. It also diverged from real AWS in few specific places based on the **Terraform version and AWS resources** I used, and those
divergences are the useful part of this article, because **the ones that threw
errors cost me minutes, and the ones that returned plausible wrong answers cost
me even more time.**

![AWS resources created against floci](aws-resources.png)

---

## First, the thing that predicts almost everything

Run `docker ps` after an apply and floci gives away its own architecture:

```
floci-floci-1              floci/floci:latest   the emulated AWS API
floci-eks-msdemo-cluster   rancher/k3s:latest   ← a real Kubernetes cluster
floci-rds-db-…             postgres:16-alpine   ← a real database
floci-ecr-registry         registry:2           ← a real OCI registry
```

floci emulates the AWS **control plane**, the API calls that create and describe
things, and delegates the **data plane** to real software it starts through the
mounted Docker socket.

That single fact predicts nearly every behaviour you will meet. Where a real
container backs the service, fidelity is high: `aws eks describe-cluster` is
emulated, but the Kubernetes API you then talk to is genuinely Kubernetes. Where
no container backs it, you get a control-plane object that faithfully records
your intent and does nothing whatsoever.

**ElastiCache and CloudFront have no container behind them. They are the two
that break.** Ten minutes with `docker ps` would have told me that before I
started.

---

## The setup is boring, which is the point

The emulator is one compose file:

```yaml
services:
  floci:
    image: floci/floci:latest
    ports:
      - "4566:4566"
      - "80:80"                  # emulated ALB listeners
      - "443:443"
      - "7000-7010:7000-7010"    # per-resource proxies, e.g. RDS
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
```

The Docker socket mount is what lets floci start those sidecars.

On the Terraform side, **nothing in `modules/` knows it is talking to an
emulator.** Terragrunt code-generates the provider into every stack:

```hcl
generate "providers" {
  path      = "tg-gen-providers.tf"
  if_exists = "overwrite_terragrunt"
  contents  = templatefile("provider-aws.tftpl", {
    endpoint_url      = local.env.aws_endpoint_url   # "" means real AWS
    endpoint_services = local.endpoint_services
    ...
  })
}
```

Set `TG_AWS_ENDPOINT_URL=""` and the same modules target a real account. The
emulator lives in one generated file, not scattered through twenty modules.

Everything else that differs is one switch in the YAML:

```yaml
global:
  floci_compat: true   # honoured in exactly three places, each commented
```

Three places. Hold that number; by the end you will know why each one exists.

---

## Seven divergences (Note: This is dependent on the terraform version I used as well as the AWS resource I deployed)

Everything below works on real AWS and doesn't work here.

### 1. CloudFront segfaults the provider, and takes bystanders with it

`CreateDistribution` succeeds. Then Terraform dies:

```
panic: runtime error: invalid memory address or nil pointer dereference
  cloudfront.resourceDistributionFlatten(...)
      internal/service/cloudfront/distribution.go:1150
```

I pulled the provider source at that exact line:

```go
// CacheBehaviors above and Restrictions below are both nil-guarded.
// OriginGroups is not.
if aws.ToInt32(distributionConfig.OriginGroups.Quantity) > 0 {
```

floci's `GetDistribution` omits `OriginGroups` entirely. Real CloudFront always
returns it, with `Quantity: 0` when empty. A missing field in the emulator meets
a missing nil check in the provider, and the plugin process dies.

**The crash isn't the interesting part. The blast radius is.** Because the plugin
died mid-apply, every resource still in flight failed with `Request cancelled`,
including an ALB and an RDS instance that floci had *already created*. Terraform
never recorded their IDs, so they were orphaned from state, and my next apply
collided with `AlreadyExists` on both.

One unsupported field on one resource cost three unrelated resources and a manual
reconciliation. There is no Terraform-side fix; v6.61.0 was current and the guard
still isn't there.

**Compat switch #1: CloudFront off.**

### 2. ElastiCache returns an endpoint that cannot exist

This one is subtler, and it's why I now distrust `describe-*` calls entirely.

`CreateReplicationGroup` succeeds. Terraform manages the resource. `describe`
reports it `available`. And it is completely unusable:

| | real AWS | floci |
|---|---|---|
| endpoint field | `NodeGroups[].PrimaryEndpoint` | `ConfigurationEndpoint` |
| endpoint value | a resolvable DNS name | the string `localhost` |
| `CreateCacheSubnetGroup` | supported | `UnsupportedOperation` |
| requested `port` | honoured | ignored, floci picks its own |
| `num_cache_clusters` | reflects reality | always `0` |
| `IncreaseReplicaCount` | supported | `UnsupportedOperation` |

Start with the field reversal. floci puts the address on
`ConfigurationEndpoint`, which for a non-clustered group on real AWS is `null`.
The value lives on `NodeGroups[].PrimaryEndpoint`. So
`primary_endpoint_address`, the attribute every example and every module uses,
comes back `null` from a resource reporting `available`.

Then the value itself: the literal string **`localhost`**. That is not an address
anything can use. To a client running inside the cluster, `localhost` is that
client's own loopback.

**This is the dangerous category.** Not an error, a plausible wrong answer. A
health check passes. A `describe-*` passes. Terraform is happy. You find out at
the point of use, several layers away from the cause.

The last two rows are bad in a different way: because floci ignores the requested
`port` and always reports `num_cache_clusters: 0`, the resource is **not
idempotent**. Port drift forces a replacement on every plan, and reconciling the
cluster count fails the apply outright with `IncreaseReplicaCount is not
supported`. The only fix is a static
`lifecycle { ignore_changes = [port, num_cache_clusters] }`, and `lifecycle`
blocks cannot be variable-driven, so that workaround is unconditional and follows
you to production.

**Compat switch #2: skip the cache subnet group.**

### 3. RDS silently destroys your database on every apply

`storage_encrypted` and `kms_key_id` are accepted at create time and read back
**unset**, whatever you sent. Both force replacement:

```
~ storage_encrypted = false -> true                # forces replacement
+ kms_key_id        = "arn:aws:kms:…"              # forces replacement
```

So every `terraform plan` wanted to destroy and recreate the database. Not drift
you can shrug at. A three-minute destroy/create cycle that drops all your data,
on a plan where you changed nothing.

The interesting part is choosing the fix. The obvious reach is `ignore_changes`,
but that means a security-relevant attribute quietly stops being enforced, on
real AWS too. Instead:

```hcl
storage_encrypted = var.floci_compat ? null : true
kms_key_id        = var.floci_compat ? null : var.kms_key_arn
```

`null` leaves the provider treating both as computed, so floci's answer is no
longer drift. With the flag false, real AWS behaviour is completely unchanged and
encryption stays fully managed. **`0 to destroy`.**

**Compat switch #3: RDS encryption attributes unmanaged locally.**

That's all three. The entire compatibility surface for 67 resources.

### 4. The load balancer cannot reach the pods

My Terraform used `target_type = "ip"`, which is correct for real EKS, where the
AWS Load Balancer Controller registers pod IPs directly with the target group. So
I registered pod IPs, and every target reported `Target.Timeout`.

Probing from inside floci's own network namespace:

```
CLOSED  10.42.0.42:4000     ← a pod
OPEN    172.18.0.5:6443     ← the k3s node
OPEN    172.18.0.6:5432     ← postgres

routes:
  default via 172.18.0.1 dev eth0
  172.18.0.0/16 dev eth0 scope link src 172.18.0.2
```

There is no route to `10.42.0.0/16`. The pod network exists only inside the k3s
container. floci's ALB can reach the *node*; it can never reach a pod.
Registering pod IPs was never going to work, regardless of my configuration.

The workaround is a NodePort. And this is the one worth flagging loudly: **my
Terraform was correct for production and wrong for the emulator, and fixing it
made my local setup less like production, not more.** That's the opposite of the
usual failure mode, and a real limitation of testing this way.

There's a sting in the tail too. Kubernetes reports the node's `InternalIP` as
`172.17.0.4`, its *default bridge* address, which floci also cannot reach. The
address that works is the node's `floci_default` address, and you have to ask
Docker for it, because Kubernetes doesn't know it exists.

### 5. The resources that apply but hold nothing

These all create cleanly, appear in state, and pass any `describe-*` check:

| Resource | On floci |
|---|---|
| `aws_iam_role` + policies | Created and readable, **never enforced.** Every call in this project uses `test`/`test` credentials and succeeds regardless of policy. |
| `aws_security_group` rules | Created and queryable, **not enforced.** Network isolation is unverifiable. |
| `aws_acm_certificate` | Reports `ISSUED` with no DNS validation and no key material. Nothing can terminate TLS with it. |
| `aws_eks_node_group` | Metadata only. The "node" is the k3s container itself, so `desired_size` does nothing and there's no autoscaling. |
| `aws_s3_bucket_server_side_encryption_configuration` | Accepted, but `head-object` never reports `ServerSideEncryption`, so you can't confirm encryption through the API. |
| VPC, subnets, route tables | Created and tagged correctly. **No packet ever traverses them**. Real connectivity is Docker networking. |

The IAM row deserves emphasis. **An over-permissive policy and a correct one are
indistinguishable here.** If your reason for testing infrastructure locally is to
catch a `"Resource": "*"` before it ships, this will not do it.

### 6. Restarting the emulator orphans the Kubernetes node

floci keeps no state across restarts, which is expected and honestly a feature
for a demo. But local Terraform state *survives on disk*, so after a restart you have
state describing infrastructure that no longer exists, and the next apply fails
on whatever does.

Less obvious: recreating floci replaces the k3s container, which means a **new
node name**. The old node object survives as `NotReady` with a dead kubelet, so
every pod bound to it can never be confirmed deleted and hangs in `Terminating`
indefinitely. Real EKS evicts these through the node-lifecycle controller.

A detail that cost me a while: `Terminating` is not a pod phase. A terminating
pod's `status.phase` is still `Running`; what marks it is
`metadata.deletionTimestamp`, which field selectors cannot filter on.

### 7. One emulator, two addresses

Anything running **in a pod** reaches floci at its Docker-network address,
`172.18.0.2:4566`. Anything running **on the host**, including every Terraform
`local-exec` provisioner, must use `localhost:4566`.

They are not interchangeable, and mixing them up gives you a bare
`Connect timeout` with nothing pointing at the cause. I passed the in-cluster
address to a provisioner that ran on the host and lost twenty minutes to it.

---

## What this changed about how I verify

Somewhere around the ElastiCache discovery I stopped trusting `describe-*`
entirely. An emulator's control plane will happily report a resource healthy when
nothing is behind it, and that is what it did.

So the verification script does **round-trips wherever a service has a data
path**:

- **KMS**: encrypt a string, decrypt it, assert the bytes match
- **S3**: put an object, get it, `cmp` against the original
- **Secrets Manager**: fetch the value, parse it, name any missing keys
- **RDS**: resolve the endpoint, TCP-probe it, run `select version()`
- **ALB**: describe listeners, count *healthy* targets, drive real traffic

Twenty-three checks. The ones that merely describe things pass against a stub;
the ones that round-trip do not.

It also detects two failure modes I met the hard way: **orphans** (live in the
emulator, absent from state, which is what a crashed provider leaves behind) and
**stale state** (the emulator restarted and state survived). Both now produce one clear
line instead of a wall of unrelated failures.

The best single artefact the project produced is this:

```
$ make vault-status
Seal Type       awskms
Initialized     true
Sealed          false
Storage Type    raft
```

`Seal Type: awskms` means Vault called `kms:Encrypt` and `kms:Decrypt` against
the emulator from inside a pod, and got real ciphertext back. Not a recorded
intention, but a cryptographic round-trip that Vault cannot start without.

![Three Vault pods on the emulated EKS cluster](k8s-vault.png)

Three of them, a real Raft cluster, scheduled by a real scheduler onto the k3s
node, every one of which had to reach `kms:Decrypt` on the emulator before it
would unseal.

ArgoCD is the same story: seven pods, reconciling the four application
Deployments from committed manifests rather than from anything Terraform
applied.

![The argocd namespace on the emulated EKS cluster](k8s-argocd.png)

Neither of these is emulated. This is the layer where a local AWS stops being a
mock and starts being a place things actually run.

---

## So is it worth it?

**For iterating on Terraform: unambiguously yes.** Ninety seconds versus
twenty-five minutes changes how you work. You stop batching changes to avoid the
wait, and you start being willing to try things. Module wiring, `for_each` keys,
variable types, dependency ordering between stacks, all exercised faithfully.

**For testing the layer above: better than I expected.** Because EKS, RDS and ECR
are real software, images really get pulled from a real registry by a real
scheduler, and real SQL hits a real database. Vault auto-unsealing through the
emulated KMS is not a simulation of anything.

**For proving your infrastructure is correct as AWS: no.** Be honest about this:

- IAM is not enforced. Security groups are not enforced.
- No TLS, no real DNS, no cross-region, no quotas, no billing.
- Some resources are shape-only. Node groups don't scale, certificates are never validated.
- And a green result can be a lie. ElastiCache proved it.

The model I've settled on: **treat it as a fast unit-test tier, not a staging
environment.** Unit tests don't prove a system works in production either. They
fail fast on the mistakes that don't need production to find, which turns out to
be most of them.

The one habit I'd pass on: **learn where the emulation stops before you trust a
green run.** For floci the rule was simple, and I found it by accident rather
than by looking. If a real container backs the service, fidelity is high. If not,
you're talking to a bookkeeping layer that will agree with everything you say.

Ten minutes with `docker ps` at the start would have saved me most of a day.

---

*The full stack, with the Terragrunt configuration, 20 Terraform modules, Vault,
ArgoCD and the 23-check verification script, is on GitHub:
[elokac/floci-aws-demo](https://github.com/elokac/floci-aws-demo). It runs with
`docker compose up -d && make up`.*
