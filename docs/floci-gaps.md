# floci fidelity gaps

What the emulator does and does not reproduce, and what each costs. Every entry
here was found by running the stack, not by reading documentation.

The pattern that predicts almost everything: **floci emulates the AWS control
plane and delegates the data plane to real containers.** Where a container
backs the service, fidelity is excellent. Where none does, you get a
control-plane object that records your intent and does nothing.

| Service | Backed by | Fidelity |
|---|---|---|
| EKS | real `rancher/k3s` container | excellent — a genuine Kubernetes API |
| RDS | real `postgres:16` container | excellent — a genuine database |
| ECR | real `registry:2` container | excellent — real image push/pull |
| ALB | HTTP proxy in the floci container | good, with one routing gap (below) |
| IAM / KMS / S3 / SSM / Secrets Manager | in-process | good — verified by round-trip |
| ElastiCache | **nothing** | poor — see below |
| CloudFront | **nothing** | unusable — crashes the AWS provider |

## ElastiCache reports an endpoint that does not exist

`CreateReplicationGroup` succeeds and Terraform manages the resource happily.
But the address comes back on `ConfigurationEndpoint` rather than
`NodeGroups[].PrimaryEndpoint` (the reverse of real AWS for a non-clustered
group), and its value is the literal string `localhost`.

Nothing listens there. From inside a pod, `localhost` is the pod's own
loopback, so a client dials itself and node-redis retries indefinitely rather
than failing fast.

That is worse than an honest error, and it caused the most subtle bug in this
project: `order-service` awaited `redis.connect()` before creating its schema,
so an unreachable cache silently prevented the `orders` table from ever being
created. Every request then failed with `relation "orders" does not exist` --
an error pointing at the database, caused by the cache.

**Handling:** `scripts/render-k8s-config.sh` treats `localhost` as "no cache"
and omits `REDIS_HOST`. `order-service` creates its schema first and connects
to the cache fire-and-forget. The application ordering fix is correct on real
AWS too: the database is required, the cache is not.

Also unsupported: `CreateCacheSubnetGroup` returns `UnsupportedOperation`, and
`IncreaseReplicaCount` is unsupported while `num_cache_clusters` always reads
back as 0. The requested `port` is ignored and floci allocates its own, which
forces a replacement on every plan. Hence the static `lifecycle.ignore_changes`
in `terraform/modules/elasticache/main.tf`.

## CloudFront crashes the AWS provider

`GetDistribution` omits `OriginGroups`. Provider v6.61.0 dereferences it
without a nil check at `distribution.go:1150`, so the plugin segfaults during
the post-create read -- taking unrelated in-flight resources down with it and
leaving them orphaned from state.

There is no Terraform-side fix; v6.61.0 was current and the guard is still
missing. CloudFront is disabled via `global.floci_compat`.

## RDS does not persist encryption attributes

`storage_encrypted` and `kms_key_id` read back as unset regardless of what was
sent, and both force replacement -- so every plan wanted to destroy and
recreate the database. Passing `null` under `floci_compat` leaves the provider
treating them as computed, which removes the drift. Real AWS is unaffected.

## The ALB cannot reach pods

`target_type = "ip"` is correct for real EKS, where the AWS Load Balancer
Controller registers pod IPs directly. floci's ALB runs inside the floci
container, which has no route to k3s's `10.42.0.0/16` -- only to the node on
the docker network. Pod targets therefore always report `Target.Timeout`.

**Handling:** the gateway Service is `type: NodePort` and
`scripts/register-alb-targets.sh` registers the node's address on the
`floci_default` network. Note that Kubernetes reports the node's `InternalIP`
as its *default bridge* address (`172.17.x`), which floci cannot reach; the
script reads the `floci_default` address from Docker instead.

This is the one case where the workaround makes the local setup *less* like
production, so it is a workaround rather than a pattern to copy.

## Two addresses for one emulator

Anything running in a pod reaches floci at its docker-network address
(`172.18.0.2:4566`). Anything running on the host -- including every Terraform
`local-exec` provisioner -- must use `localhost:4566`. They are not
interchangeable, and mixing them produces a bare `Connect timeout`.

`composite-standard` keeps them as separate locals (`in_cluster_endpoint` and
`host_endpoint`) for exactly this reason.

## floci keeps no state across restarts

Recreating the container discards everything while local Terraform state
survives on disk, leaving state describing infrastructure that no longer
exists. `verify.sh` detects this and says so rather than emitting a wall of
unrelated failures.
