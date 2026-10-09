#------------------------------------------------------------------
# Module: ArgoCD
#------------------------------------------------------------------
# Terraform provisions the platform; ArgoCD owns the workloads. The boundary
# is the `path` below -- everything under it is reconciled from git, which is
# why k8s/gcp carries real image references rather than a PLACEHOLDER patched
# in afterwards by `kubectl set image`. Port of the AWS argocd module; the
# admin password hook writes to Secret Manager via REST instead of the CLI.
#------------------------------------------------------------------

resource "kubernetes_namespace" "floci_argocd_namespace" {
  for_each = local.installs

  metadata {
    name   = each.value.namespace
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

resource "helm_release" "floci_argocd" {
  for_each = local.installs

  name       = each.key
  namespace  = kubernetes_namespace.floci_argocd_namespace[each.key].metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = each.value.chart_version

  values = [yamlencode({
    # Single-node k3s: the HA topology would leave replicas Pending.
    redis-ha       = { enabled = false }
    controller     = { replicas = 1 }
    repoServer     = { replicas = 1 }
    applicationSet = { replicas = 1 }

    server = {
      replicas = 1
      # TLS terminates nowhere useful in the demo; plain HTTP keeps
      # port-forward simple.
      extraArgs = ["--insecure"]
    }

    configs = {
      params = { "server.insecure" = true }
    }
  })]

  wait    = true
  timeout = 900
}

#------------------------------------------------------------------
# The managed Application
#------------------------------------------------------------------
# Installed with Argo's own argocd-apps chart rather than a
# kubernetes_manifest resource. kubernetes_manifest validates against the live
# API *at plan time*, so it requires the argoproj.io/Application CRD to already
# exist -- but that CRD arrives with the argo-cd chart in this same apply.
# Helm does no such plan-time validation, so a second release sidesteps the
# ordering problem entirely and keeps the Application declarative.
#------------------------------------------------------------------

resource "helm_release" "floci_argocd_apps" {
  for_each = local.installs

  name       = "${each.key}-apps"
  namespace  = kubernetes_namespace.floci_argocd_namespace[each.key].metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = each.value.apps_chart_version

  # argocd-apps v2 keys `applications` by name. Passing a list makes the chart
  # use the list INDEX as metadata.name, which fails to decode.
  values = [yamlencode({
    applications = {
      (var.global_config.client_name) = {
        namespace = each.value.namespace
        project   = "default"

        source = {
          repoURL        = each.value.repo_url
          targetRevision = each.value.target_revision
          path           = each.value.path
        }

        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = each.value.destination_namespace
        }

        syncPolicy = each.value.auto_sync ? {
          automated = {
            prune    = each.value.prune
            selfHeal = each.value.self_heal
          }
          syncOptions = ["CreateNamespace=true"]
        } : null
      }
    }
  })]

  depends_on = [helm_release.floci_argocd]
}

#------------------------------------------------------------------
# Admin password -> Secret Manager
#------------------------------------------------------------------
# The chart generates the initial password into a k8s Secret that it deletes
# once changed. Copying it out makes it retrievable the same way the AWS port
# exposes it, written through the emulator REST API because the CLI has no
# Secret Manager equivalent here.
#------------------------------------------------------------------

resource "null_resource" "floci_argocd_admin_password" {
  for_each = local.password_secrets

  triggers = {
    release = helm_release.floci_argocd[each.key].id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      NAMESPACE   = each.value.namespace
      SECRET_NAME = each.value.admin_password_secret_name
      ENDPOINT    = each.value.gcp_endpoint_url
      PROJECT     = each.value.gcp_project
    }
    command = <<-BASH
      set -uo pipefail

      PW=$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode)

      if [ -z "$PW" ]; then
        echo "no argocd-initial-admin-secret found (already rotated?); skipping"
        exit 0
      fi

      DATA=$(printf '%s' "$PW" | base64 -w0)
      curl -s -m 15 -X POST \
        "$ENDPOINT/v1/projects/$PROJECT/secrets/$SECRET_NAME:addVersion" \
        -H "Content-Type: application/json" \
        -d "{\"payload\":{\"data\":\"$DATA\"}}" >/dev/null \
        && echo "argocd admin password -> secretmanager://$SECRET_NAME"
    BASH
  }
}
