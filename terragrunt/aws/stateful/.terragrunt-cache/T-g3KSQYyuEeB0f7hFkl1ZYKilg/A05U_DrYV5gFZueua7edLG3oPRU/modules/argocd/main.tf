#------------------------------------------------------------------
# Module: ArgoCD
#------------------------------------------------------------------
# Terraform provisions the platform; ArgoCD owns the workloads. The boundary
# is the `path` below -- everything under it is reconciled from git, which is
# why k8s/ carries real image references rather than a PLACEHOLDER patched in
# afterwards by `kubectl set image`.
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

resource "kubernetes_manifest" "floci_argocd_application" {
  for_each = local.installs

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = var.global_config.client_name
      namespace = kubernetes_namespace.floci_argocd_namespace[each.key].metadata[0].name
    }
    spec = {
      project = "default"
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

  depends_on = [helm_release.floci_argocd]
}

#------------------------------------------------------------------
# Admin password -> Secrets Manager
#------------------------------------------------------------------
# The chart generates the initial password into a k8s Secret that it deletes
# once changed. Copying it out makes it retrievable the same way Vault's root
# token is, rather than requiring a kubectl incantation.
#------------------------------------------------------------------

resource "null_resource" "floci_argocd_admin_password" {
  for_each = local.password_secrets

  triggers = {
    release = helm_release.floci_argocd[each.key].id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      NAMESPACE    = each.value.namespace
      SECRET_NAME  = each.value.admin_password_secret_name
      AWS_ENDPOINT = each.value.aws_endpoint_url
    }
    command = <<-BASH
      set -uo pipefail
      export AWS_ACCESS_KEY_ID="$${AWS_ACCESS_KEY_ID:-test}"
      export AWS_SECRET_ACCESS_KEY="$${AWS_SECRET_ACCESS_KEY:-test}"
      export AWS_DEFAULT_REGION="$${AWS_DEFAULT_REGION:-us-east-1}"

      PW=$(kubectl -n "$NAMESPACE" get secret argocd-initial-admin-secret \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 --decode)

      if [ -z "$PW" ]; then
        echo "no argocd-initial-admin-secret found (already rotated?); skipping"
        exit 0
      fi

      aws --endpoint-url "$AWS_ENDPOINT" secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME" --secret-string "$PW" >/dev/null \
        && echo "argocd admin password -> secretsmanager://$SECRET_NAME"
    BASH
  }
}
