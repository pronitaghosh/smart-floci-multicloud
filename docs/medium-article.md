# I Ran a Full AWS Microservices Stack on My Laptop — and Broke It Seven Ways

## Testing Terraform locally with floci: what worked, what didn't, and what an emulator can't tell you

---

Terraform's feedback loop against real AWS is punishing. An EKS cluster takes
about fifteen minutes to create and ten to tear down. Get a security group rule
wrong and you've spent half an hour finding out. Multiply that by the number of
times you iterate on a module and the arithmetic gets depressing.

So I tried the obvious thing: run the whole stack locally. Not a subset, not
mocks — a real Terraform config with a VPC, EKS, RDS, an ALB, ECR, S3, KMS,
Secrets Manager and SSM, applied against [floci](https://floci.io), an AWS
emulator that runs in Docker. Then deploy four actual Node microservices onto
it and drive traffic through the load balancer.

It worked. Fifty-two Terraform resources, four services, a Postgres-backed
order flow, all on a MacBook with no AWS account attached.

It also broke seven times, and the breakages turned out to be the most useful
part. Some were my bugs. Some were the emulator's. Telling those apart is the
entire skill of using a tool like this, so that's what most of this article is
about.

![Architecture diagram](architecture.png)

*The full topology. Note the two boxes that matter: floci runs the AWS control
plane, but EKS, RDS and ECR are real containers it starts for you.*

---

## What floci actually does

The thing that surprised me most is how little of floci is pretending.

Run `docker ps` after a `terraform apply` and you find this:

```
floci-floci-1                floci/floci:latest    0.0.0.0:4566->4566/tcp
floci-eks-msdemo-cluster     rancher/k3s:latest    0.0.0.0:6501->6443/tcp
floci-rds-db-D538E5F194BA…   postgres:16-alpine    5432/tcp
floci-ecr-registry           registry:2            0.0.0.0:5100->5000/tcp
```

That's a genuine k3s cluster, a genuine Postgres, and a genuine OCI registry.
floci emulates the *control plane* — the AWS API calls that create and describe
things — and delegates the data plane to real software. `aws eks
describe-cluster` is emulated; the Kubernetes API you then talk to is not.

This distinction predicts almost everything that follows. Where floci has a
real container behind a service, fidelity is excellent. Where it doesn't, you
get a control-plane object that records your intent and does nothing.

CloudFront falls in the second category and bit me hard. ElastiCache sits
awkwardly between the two — emulated, but reporting itself in a shape the
provider doesn't expect.

---

## Setting it up

The whole emulator is one compose file:

```yaml
services:
  floci:
    image: floci/floci:latest
    ports:
      - "4566:4566"
      - "80:80"        # emulated ALB listeners
      - "443:443"
      - "7000-7010:7000-7010"   # per-resource proxies (e.g. RDS)
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
```

The Docker socket mount is what lets floci start those sidecar containers. The
extra ports are not in floci's default example, and leaving them out cost me an
hour later — more on that below.

The Terraform side is just endpoint overrides:

```hcl
provider "aws" {
  region                      = var.aws_region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2  = var.floci_endpoint
    eks  = var.floci_endpoint
    rds  = var.floci_endpoint
    # ... one line per service
  }
}
```

Every module is ordinary Terraform. Nothing in `modules/` knows it's talking to
an emulator, which is the point — the same code should apply to real AWS.

Then `terraform apply`, and about ninety seconds later you have a VPC, an EKS
cluster, a Postgres instance and a load balancer.

---

## The seven things that broke

### 1. `count` on a value that doesn't exist yet

```
Error: Invalid count argument

  on modules/alb/main.tf line 96:
  96:   count = var.acm_certificate_arn != "" ? 1 : 0

The "count" value depends on resource attributes that cannot be determined
until apply.
```

This one isn't floci's fault at all — it's a pure Terraform mistake that would
fail identically against real AWS. `count` is evaluated during **plan**, before
anything is created. The certificate ARN comes from `aws_acm_certificate.this`,
which doesn't exist yet, so Terraform genuinely cannot know whether to make one
listener or zero.

The fix is to gate on something known at plan time — an input variable rather
than a resource attribute:

```hcl
variable "enable_https" {
  type    = bool
  default = false
}

resource "aws_lb_listener" "https" {
  count           = var.enable_https ? 1 : 0
  certificate_arn = var.acm_certificate_arn   # unknown values are fine HERE
}
```

The distinction worth internalising: attribute *values* may be unknown at plan
time. Only `count` and `for_each` must be known. Passing the still-unknown ARN
into `certificate_arn` is perfectly legal.

**Verdict: my bug.** And catching it in ninety seconds instead of fifteen
minutes is exactly why I was doing this locally.

### 2. The AWS provider segfaulted

```
Stack trace from the terraform-provider-aws_v6.61.0_x5 plugin:
panic: runtime error: invalid memory address or nil pointer dereference

cloudfront.resourceDistributionFlatten(...)
        internal/service/cloudfront/distribution.go:1150
```

A provider crash mid-apply, taking my ALB and RDS with it — both reported
`Request cancelled` even though floci had already created them.

I pulled the provider source at that exact line:

```go
// distribution.go:1150
if aws.ToInt32(distributionConfig.OriginGroups.Quantity) > 0 {
```

The lines above and below it nil-check `CacheBehaviors` and `Restrictions`.
`OriginGroups` is not checked. And floci's `GetDistribution` response omits
`OriginGroups` entirely — real CloudFront always returns it with `Quantity: 0`.

So: a missing field in the emulator meets a missing nil-check in the provider,
and the plugin process dies. I confirmed it by creating a distribution through
the CLI and diffing the response against the AWS API shape — `OriginGroups`,
`Restrictions` and `ForwardedValues` were all absent.

There is no Terraform-side fix. Upgrading doesn't help; v6.61.0 was the latest
release and the guard still isn't there. CloudFront gets disabled for local
runs.

**Verdict: emulator gap plus a provider bug.** This is the failure mode people
should worry about with emulators — not "it didn't work" but "it took down
unrelated resources while failing".

The knock-on matters too. Because the provider died before recording IDs,
floci had a load balancer, a database and a distribution that Terraform knew
nothing about. My next apply hit `CNAMEAlreadyExists`. Orphan detection became
a permanent part of my verification script after that.

### 3. ElastiCache works — but tells you the endpoint somewhere else

```
Error: creating ElastiCache Subnet Group: UnsupportedOperation:
Operation CreateCacheSubnetGroup is not supported.
```

My first conclusion was "ElastiCache isn't emulated". That was wrong, and worth
correcting because the real behaviour is more interesting.

Only the *subnet group* is unsupported. `CreateReplicationGroup` works, and
Terraform manages the resource happily — I verified it in a throwaway project:

```
aws_elasticache_replication_group.t: Creation complete after 30s [id=tf-probe-rg]

Outputs:
config_endpoint = "localhost"
```

The trap is *which field* carries the address. Real AWS populates
`NodeGroups[].PrimaryEndpoint` for a non-clustered group and leaves
`ConfigurationEndpoint` null. floci does the exact opposite — it has no
`NodeGroups` key at all. So `primary_endpoint_address`, the attribute every
example uses, comes back `null` while the cache is genuinely reachable at
`localhost:6379`.

An apply that "succeeds" and hands your application a null endpoint is worse
than an honest error, and it's the strongest argument for round-trip testing: a
`describe-*` call reports the cache `available` either way.

Taking whichever field is set keeps one module correct on both:

```hcl
output "primary_endpoint" {
  value = try(coalesce(
    aws_elasticache_replication_group.this.primary_endpoint_address,
    aws_elasticache_replication_group.this.configuration_endpoint_address,
  ), null)
}
```

I also made caching optional in `order-service`, so an absent cache degrades
instead of failing:

```js
const cacheEnabled = Boolean(process.env.REDIS_HOST);
const redis = cacheEnabled ? createClient({ /* ... */ }) : null;

async function cacheGet(key) {
  if (!redis?.isOpen) return null;
  try { return await redis.get(key); } catch { return null; }
}
```

**Verdict: a shape mismatch, not a missing service** — and my own premature
conclusion. The subnet group is an honest `UnsupportedOperation`; the endpoint
field is the part that quietly misleads.

### 4. A tab character ate my password

This is my favourite, because it's a bug in *my* shell script that produced a
plausible-looking wrong answer.

I generate a Kubernetes ConfigMap from Terraform outputs and Secrets Manager.
To split three fields I used a tab delimiter — the classic move when values
might contain spaces:

```bash
IFS=$'\t' read -r DB_USER DB_PASSWORD DB_NAME <<<"$(...)"
```

The generated file came out as:

```yaml
DB_NAME: ""
DB_USER: "msdemo_admin"
DB_PASSWORD: "msdemo"       # <- that's the database name
```

Every field had shifted left by one. **Tab is an IFS whitespace character**, so
bash collapses runs of tabs into a single delimiter — `user\t\tdbname` splits
into two fields, not three. My empty password field vanished and the database
name slid into its place.

Compounding it, I was reading the wrong keys (`username`/`password` when the
secret writes `db_username`/`db_password`), so the password was empty in the
first place. And my "is the password empty?" guard passed, because by then it
contained the string `msdemo`.

The fix is a non-whitespace delimiter:

```bash
IFS=$'\x1f' read -r DB_USER DB_PASSWORD DB_NAME <<<"$(...)"
```

Demonstrable in two lines:

```bash
$ IFS=$'\t'   read -r a b c <<<"$(printf 'user\t\tdbname')"; echo "[$a][$b][$c]"
[user][dbname][]          # shifted

$ IFS=$'\x1f' read -r a b c <<<"$(printf 'user\x1f\x1fdbname')"; echo "[$a][$b][$c]"
[user][][dbname]          # correct
```

**Verdict: entirely my bug**, and one that would have shipped a broken
ConfigMap to production just as happily.

### 5. `COPY` smuggled host file permissions into the image

All four services crash-looped:

```
Error: EACCES: permission denied, open '/app/server.js'
```

My Dockerfile did the sensible thing and dropped privileges:

```dockerfile
COPY package.json ./
RUN npm install --omit=dev
COPY server.js ./
USER node
CMD ["node", "server.js"]
```

The `server.js` files on my Mac were mode `0600`. `COPY` **preserves source
permissions**, so inside the image they were root-owned and unreadable by the
`node` user. `package.json` was `0644`, which is why `npm install` succeeded and
only the entry file failed — a nicely misleading clue.

```dockerfile
COPY --chown=node:node --chmod=644 package.json ./
RUN npm install --omit=dev
COPY --chown=node:node --chmod=644 server.js ./
USER node
```

**Verdict: my bug**, and a portable one — nothing about it is floci-specific.

### 6. The fix for #5 did nothing, for a completely different reason

I rebuilt, pushed, restarted the rollout. Identical `EACCES`.

The image digest told the story:

```
spec:   …/msdemo/payment-service:latest
status: …/payment-service@sha256:63d946a2…   ← the OLD digest
policy: IfNotPresent
```

Kubernetes never pulled the new image. My manifests used a placeholder:

```yaml
image: PLACEHOLDER   # replaced later by kubectl set image
```

Kubernetes defaults `imagePullPolicy` to `Always` **only when the tag is
literally `:latest`**. `PLACEHOLDER` is untagged, so it defaulted to
`IfNotPresent` — and that default was baked into the Deployment template at
creation. `kubectl set image` rewrites the image reference but never the policy.
Every rollout since had been re-running the cached, broken image.

```yaml
image: PLACEHOLDER
imagePullPolicy: Always
```

**Verdict: my bug**, and the expensive one. Bugs #5 and #6 stacked so that
fixing the real problem produced no visible change. Without checking the actual
`imageID`, I'd have concluded the permission fix was wrong and gone looking in
the wrong place.

That's the general lesson: when a correct fix appears to do nothing, verify
that your fix is the thing running.

### 7. The ALB couldn't reach the pods

Everything healthy, and the load balancer's targets stuck on:

```
Target.Timeout — Request timed out
```

My Terraform used `target_type = "ip"`, which is correct for real EKS: the AWS
Load Balancer Controller registers pod IPs directly with the target group. So I
registered pod IPs, `10.42.0.x`.

Probing from inside the floci container's network namespace:

```
  CLOSED  10.42.0.42:4000     ← a pod
  OPEN    172.18.0.5:6443     ← the k3s node
  OPEN    172.18.0.6:5432     ← postgres

routes:
  default via 172.18.0.1 dev eth0
  172.18.0.0/16 dev eth0 scope link src 172.18.0.2
```

There's no route to `10.42.0.0/16`. The pod network exists only inside the k3s
container. floci's ALB can reach the *node*, never the pods — so registering
pod IPs could never work, regardless of my application.

The workaround is a NodePort:

```yaml
spec:
  type: NodePort
  ports:
    - port: 4000
      nodePort: 30080
```

and registering the node's address on the Docker network instead. One wrinkle:
Kubernetes reports the node's `InternalIP` as `172.17.0.4` — its *default
bridge* address — while floci can only reach it at `172.18.0.5` on the
`floci_default` network. The address Kubernetes gives you is the wrong one.

After that, targets went `healthy` and the full chain worked:

```json
{"id":1,"user_id":1,"item":"widget","amount_cents":4200,"status":"paid",
 "payment":{"status":"charged","transaction_id":"mock_txn_1787619673391"}}
```

ALB → gateway → order-service → Postgres → payment-service → back.

**Verdict: emulator gap, and an instructive one.** My Terraform was *correct
for production* and wrong for the emulator. That's the opposite of the usual
failure, and it's a genuine limitation of testing this way: the workaround
makes the local environment less like production, not more.

---

## A digression on verifying emulators

Somewhere around bug #3 I stopped trusting `describe-*` calls.

An emulator's control plane will happily tell you a cache cluster is
`available` when nothing is behind it. So my verification script does
round-trips wherever a service has a data path:

- **KMS** — encrypt a string, decrypt it, assert the bytes match
- **S3** — put an object, get it, `cmp` against the original
- **Secrets Manager** — fetch the value, parse it, name any missing keys
- **RDS** — resolve the endpoint, TCP-probe it, run `select version()`
- **ALB** — describe listeners, count healthy targets, drive real traffic

Twenty-three checks. The ones that only *describe* things pass against a stub;
the ones that round-trip do not.

It also detects two failure modes I'd hit the hard way:

**Orphans** — resources live in the emulator but absent from state, which is
what a crashed provider leaves behind. Matching on identifiers rather than
resource types matters here: a type-level check passes happily when the
emulator has two load balancers and Terraform knows about one.

**Stale state** — the reverse. floci keeps nothing across restarts, but
`terraform.tfstate` is a local file that survives. After a `docker compose
down` my inventory still listed all fifty-two resources while every live check
failed. Two sources of truth disagreeing, with no signal about which to
believe. Now it checks freshness first and says so in one line.

---

## So is this worth doing?

For iterating on Terraform: unambiguously yes. Ninety seconds versus twenty-five
minutes changes how you work. You stop batching changes to avoid the wait, and
you start being willing to try things.

For catching *your own* bugs: also yes. Four of my seven were mine, and every
one of them — the `count` mistake, the tab delimiter, the file permissions, the
pull policy — would have behaved identically against real AWS. Finding them
locally cost minutes.

For validating that your infrastructure is production-correct: **no**, and it's
important to be honest about this. Bug #7 is the proof. My ALB configuration
was right for real EKS and wrong for the emulator, and the fix made my local
setup *less* representative. An emulator can tell you your Terraform is
syntactically valid, internally consistent, and that your application logic
works. It cannot tell you your IAM policies are correct, that your security
groups are tight enough, or that a real ALB will route the way you expect.

The mental model I've settled on: **treat it as a fast unit-test tier, not as a
staging environment.** Unit tests don't prove your system works in production
either. They fail fast on the mistakes that don't need production to find, which
turns out to be most of them.

The other thing I'd tell anyone starting: learn where the emulation stops before
you trust a green result. For floci, the rule proved simple — if there's a real
container behind the service, fidelity is high. If there isn't, you're talking
to a bookkeeping layer. Ten minutes with `docker ps` tells you which is which,
and that's ten minutes better spent than the hour I lost to CloudFront.

---

*The full stack — Terraform, four microservices, deployment scripts, and the
23-check verification script — is on GitHub:
[elokac/floci-aws-demo](https://github.com/elokac/floci-aws-demo). It runs with
`docker compose up -d && ./scripts/rebuild-all.sh`.*
