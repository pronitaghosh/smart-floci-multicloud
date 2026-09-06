# Where floci diverges from real AWS

**Inclusion criterion:** everything below is Terraform or AWS-API behaviour that
**works on real AWS and does not work, or works differently, on floci.**

Everything here was found by applying the stack, not by reading documentation.
Each entry has been reproduced on its own, away from the full 67-resource
apply, so the cause is the emulator and not something else in the stack.

![AWS resources created against floci](aws-resources.png)

---

## The rule that predicts almost all of it

floci emulates the AWS **control plane** and delegates the **data plane** to real
containers it starts through the mounted Docker socket:

```
floci-eks-msdemo-cluster   rancher/k3s      a genuine Kubernetes API
floci-rds-db-…             postgres:16      a genuine database
floci-ecr-registry         registry:2       a genuine OCI registry
```

Where a container backs the service, fidelity is high. Where none does, you get
a control-plane object that records your intent and does nothing. **ElastiCache
and CloudFront have no container behind them, and they are the two that break.**

---

## 1. CloudFront segfaults the AWS provider

**Severity: fatal.** It takes unrelated resources down with it.

`CreateDistribution` succeeds. The provider then crashes reading the response
back:

```
panic: runtime error: invalid memory address or nil pointer dereference
  cloudfront.resourceDistributionFlatten(...)
      internal/service/cloudfront/distribution.go:1150
```

floci's `GetDistribution` omits `OriginGroups` entirely. Real CloudFront always
returns it, with `Quantity: 0` when empty. Provider v6.61.0 dereferences it
without a nil check:

```go
// distribution.go:1150. CacheBehaviors and Restrictions, above and below,
// are nil-guarded. OriginGroups is not.
if aws.ToInt32(distributionConfig.OriginGroups.Quantity) > 0 {
```

**Why it matters beyond CloudFront:** the plugin *process* dies, so every
resource still in flight fails with `Request cancelled` or `Plugin did not
respond`, even though floci had already created them. Terraform never records
their IDs, so they are orphaned from state and the next apply collides with
`AlreadyExists`. One unsupported field cost an ALB, an RDS instance and a
distribution in a single run.

There is no Terraform-side fix; v6.61.0 was current and the guard is still
absent. **Handling:** disabled via `global.floci_compat`.

## 2. ElastiCache returns an endpoint that does not exist

**Severity: high.** It succeeds while producing an unusable result.

The replication group applies and Terraform manages it. Four divergences:

| | real AWS | floci |
|---|---|---|
| endpoint field | `NodeGroups[].PrimaryEndpoint` | `ConfigurationEndpoint` |
| endpoint value | a resolvable DNS name | the literal string `localhost` |
| `CreateCacheSubnetGroup` | supported | `UnsupportedOperation` |
| requested `port` | honoured | ignored; floci allocates its own |
| `num_cache_clusters` | reflects reality | always reads back `0` |
| `IncreaseReplicaCount` | supported | `UnsupportedOperation` |

The endpoint reversal alone makes `primary_endpoint_address`, the attribute
every example uses, return `null` on a resource that reports `available`.

The value is worse than the field. `localhost` is not an address anything can
use: to a client inside the cluster it is that client's own loopback. **This is
the most dangerous category of emulator behaviour: not an error, but a plausible
wrong answer.** A `describe-*` check reports the cache healthy.

The `port` and `num_cache_clusters` divergences also make the resource
non-idempotent: `port` drift forces a replacement on every plan, and
reconciling `num_cache_clusters` fails the apply outright.

**Handling:** `terraform/modules/elasticache/main.tf` carries a static
`lifecycle { ignore_changes = [port, num_cache_clusters] }`. A `lifecycle` block
cannot be variable-driven, so it is unconditional. The subnet group is skipped under
`floci_compat`, and the endpoint output coalesces both fields so one module is
correct on both targets.

## 3. RDS does not persist encryption attributes

**Severity: medium.** It silently destroys the database on every apply.

`storage_encrypted` and `kms_key_id` are accepted at create time and read back
**unset**, regardless of what was sent. Both force replacement, so every plan
wanted to destroy and recreate the instance, a ~3 minute cycle that also drops
all data:

```
~ storage_encrypted = false -> true  # forces replacement
+ kms_key_id        = "arn:aws:kms:…" # forces replacement
```

**Handling:** passing `null` under `floci_compat` leaves the provider treating
both as computed, which removes the drift. Real AWS is unaffected: with the flag
false, encryption is configured exactly as before and stays fully managed.
Preferred over `ignore_changes` precisely because no security-relevant setting
quietly stops being enforced.

## 4. The ALB has no route to the pod network

**Severity: medium.** Correct Terraform produces a broken data path.

`target_type = "ip"` is right for real EKS, where the AWS Load Balancer
Controller registers pod IPs directly. floci's ALB runs inside the floci
container, whose route table contains only the Docker network:

```
default via 172.18.0.1 dev eth0
172.18.0.0/16 dev eth0 scope link src 172.18.0.2
```

There is no route to k3s's `10.42.0.0/16`, so pod targets always report
`Target.Timeout`. Verified: `172.18.0.5:6443` (the node) and `172.18.0.6:5432`
(Postgres) are reachable; `10.42.0.42:4000` (a pod) is not.

**Note this is the one case where the workaround makes the local environment
*less* like production**, not more: the demo switches the Service to `NodePort`
and registers the node. There is a second wrinkle. Kubernetes reports the node's
`InternalIP` as its *default bridge* address (`172.17.x`), which floci also
cannot reach, so the node's `floci_default` address must be read from Docker.

## 5. Services that apply but carry no substance

These create cleanly and would mislead anyone checking only `describe-*`:

| Resource | On floci |
|---|---|
| `aws_iam_role` + policies | Created and readable, **never enforced**. Every call in this project uses `test`/`test` credentials and succeeds regardless of policy. A wide-open policy is indistinguishable from a correct one. |
| `aws_security_group` rules | Created and queryable, **not enforced**. Network isolation is unverifiable. |
| `aws_acm_certificate` | Reports `ISSUED` without DNS validation and with no key material, so nothing can actually terminate TLS. |
| `aws_eks_node_group` | Metadata only. The "node" is the k3s container itself, so `desired_size` has no effect and there is no autoscaling. |
| `aws_s3_bucket_server_side_encryption_configuration` | Accepted, but `head-object` does not report `ServerSideEncryption`, so encryption cannot be confirmed through the API. |
| VPC / subnets / route tables | Created, tagged and queryable, but no packet traverses them. Real connectivity is Docker networking. |

## 6. floci discards all state when its container is recreated

**Severity: operational.**

Recreating the container wipes every resource while local Terraform state
survives on disk, leaving state describing infrastructure that no longer exists.
The next apply then fails on whatever *does* still exist.

It also **orphans the previous Kubernetes node**: the node object survives as
`NotReady` with a dead kubelet, so any pod bound to it can never be confirmed
deleted and hangs in `Terminating` indefinitely. Real EKS evicts these via the
node-lifecycle controller.

![Pods stuck Terminating on an orphaned node](k8s-workloads.png)

Everything healthy sits on `2851b46f1…`. The three `Terminating` rows,
`coredns`, `local-path-provisioner` and `metrics-server`, are bound to
`d3818b214…` and are **11 days old**. They are not shutting down slowly. They are
waiting for a kubelet that no longer exists to confirm it released them, which it
never will.

Both nodes are still there eleven days later:

```
$ kubectl get nodes -o wide
NAME           STATUS     ROLES           AGE   VERSION        INTERNAL-IP
2851b46f1118   Ready      control-plane   29h   v1.34.1+k3s1   172.17.0.3
d3818b21468e   NotReady   control-plane   11d   v1.34.1+k3s1   172.17.0.3
```

`d3818b21468e` is a k3s container that no longer exists. Its `coredns`,
`local-path-provisioner` and `metrics-server` pods have been `Terminating` for
those eleven days and will stay that way until the node object is deleted by
hand. Nothing is left to confirm the kubelet ever released them:

```
kubectl delete node d3818b21468e --force
```

Note also that both nodes report the same `INTERNAL-IP`, `172.17.0.3`. That is
the Docker *default bridge* address, not the address on floci's own network. It
is the same reason the ALB cannot reach the node by the address Kubernetes
advertises (divergence 4).

**Handling:** `verify.sh` checks state freshness before running any probe and
says so in one line rather than emitting a wall of unrelated failures.

## 7. One emulator, two addresses

**Severity: operational.** It produces a bare `Connect timeout` with no hint.

Anything running **in a pod** reaches floci at its Docker-network address
(`172.18.0.2:4566`). Anything running **on the host**, including every Terraform
`local-exec` provisioner, must use `localhost:4566`. They are not
interchangeable, and no error message points at the distinction.

`composite-standard` keeps them as separate locals (`in_cluster_endpoint`,
`host_endpoint`) for exactly this reason.

---

## Summary

| # | Divergence | Would work on real AWS | Fatal? |
|---|---|---|---|
| 1 | CloudFront response missing `OriginGroups` → provider segfault | yes | yes, orphans unrelated resources |
| 2 | ElastiCache endpoint is `localhost`, on the wrong field | yes | no, but silently unusable |
| 3 | RDS drops `storage_encrypted` / `kms_key_id` | yes | no, but destroys data every apply |
| 4 | ALB cannot route to the pod CIDR | yes | no, needs a NodePort workaround |
| 5 | IAM, SGs, ACM, node groups create but carry no substance | yes | no, but unverifiable |
| 6 | All state lost on container recreate; k8s node orphaned | n/a | operational |
| 7 | Different endpoint address from host vs pod | n/a | operational |

**The pattern:** floci fails safely where it says `UnsupportedOperation`, and
fails dangerously where it returns a plausible value: a `localhost` endpoint, an
`ISSUED` certificate nothing can serve, an `available` cache with nothing behind
it. The first kind you plan around in an afternoon. The second kind you only find
by running the thing.
