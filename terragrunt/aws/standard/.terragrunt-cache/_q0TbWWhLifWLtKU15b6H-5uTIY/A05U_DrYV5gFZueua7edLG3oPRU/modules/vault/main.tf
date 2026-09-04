#------------------------------------------------------------------
# Module: Vault
#------------------------------------------------------------------
# Deploys Vault into Kubernetes, initialises it, and writes the root token
# into AWS Secrets Manager. Mirrors the reference repo's approach: the
# hashicorp/vault Terraform provider is deliberately NOT used -- the CLI is
# driven through kubectl exec, so no token is ever held in terraform state.
#------------------------------------------------------------------

resource "kubernetes_namespace" "floci_vault_namespace" {
  for_each = local.clusters

  metadata {
    name   = each.value.namespace
    labels = { "app.kubernetes.io/managed-by" = "terraform" }
  }
}

resource "helm_release" "floci_vault" {
  for_each = local.clusters

  name       = each.key
  namespace  = kubernetes_namespace.floci_vault_namespace[each.key].metadata[0].name
  repository = "https://helm.releases.hashicorp.com"
  chart      = "vault"
  version    = each.value.chart_version

  # floci's k3s is a single node, so the anti-affinity the chart sets by
  # default would leave replicas 2 and 3 permanently Pending.
  values = [yamlencode({
    server = {
      ha = {
        enabled  = each.value.replicas > 1
        replicas = each.value.replicas
        raft = {
          enabled = true
          config = <<-HCL
            ui = true
            listener "tcp" {
              tls_disable = 1
              address     = "[::]:8200"
              cluster_address = "[::]:8201"
            }
            storage "raft" {
              path = "/vault/data"
            }
            ${each.value.auto_unseal ? <<-SEAL
            seal "awskms" {
              region     = "${each.value.aws_region}"
              kms_key_id = "${each.value.unseal_key_id}"
              endpoint   = "${each.value.kms_endpoint}"
            }
            SEAL
        : ""}
            service_registration "kubernetes" {}
          HCL
      }
    }

    affinity = ""

    dataStorage = {
      enabled = each.value.data_storage
      size    = each.value.data_storage_size
    }

    extraEnvironmentVars = merge(
      local.seal_env,
      {
        AWS_REGION                = each.value.aws_region
        AWS_EC2_METADATA_DISABLED = "true"
      }
    )
    }

    injector = { enabled = false }
    ui       = { enabled = true }
})]

# The chart reports ready once pods are Running; they are sealed until
# operator init runs, which is the provisioner below.
wait          = true
wait_for_jobs = false
timeout       = 600
}

#------------------------------------------------------------------
# Initialisation
#------------------------------------------------------------------
# `vault status` exits 2 when sealed and 1 when the API is unreachable, so a
# plain exit-code check cannot tell "not ready yet" from "sealed". The script
# parses the JSON instead and retries until the API answers at all.
#------------------------------------------------------------------

resource "null_resource" "floci_vault_init" {
  for_each = local.clusters

  triggers = {
    cluster = each.key
    release = helm_release.floci_vault[each.key].id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      NAMESPACE       = each.value.namespace
      RELEASE         = each.key
      ROOT_SECRET     = each.value.root_token_secret_name
      RECOVERY_SECRET = each.value.recovery_keys_secret_name
      AWS_ENDPOINT    = each.value.aws_endpoint_url
      AUTO_UNSEAL     = tostring(each.value.auto_unseal)
    }
    command = file("${path.module}/scripts/vault-init.sh")
  }
}
