locals {
  api = {
    image_tag = "0.11.2"
  }
}

module "api_redis" {
  source = "github.com/serlo/infrastructure-modules-shared.git//redis?ref=34a6da8a720f4b8b3a381d57551f4c6bf6de1249"

  namespace     = kubernetes_namespace.api_namespace.metadata.0.name
  chart_version = "10.5.7"
  image_tag     = "4.0.14"
}

module "api_secrets" {
  source = "github.com/serlo/infrastructure-modules-api.git//secrets?ref=342c7f3b0a39e026a918e69c37f1ec9b97357594"
}

module "api_server" {
  source = "github.com/serlo/infrastructure-modules-api.git//server?ref=342c7f3b0a39e026a918e69c37f1ec9b97357594"

  namespace         = kubernetes_namespace.api_namespace.metadata.0.name
  image_tag         = local.api.image_tag
  image_pull_policy = "IfNotPresent"

  secrets              = module.api_secrets
  redis_host           = "redis-master"
  hydra_host           = module.hydra.admin_uri
  serlo_org_ip_address = module.serlo_org.server_service_ip_address

  active_donors_data = {
    google_api_key        = var.api_active_donors_google_api_key
    google_spreadsheet_id = var.api_active_donors_google_spreadsheet_id
  }

  sentry_dsn         = "https://dd6355782e894e048723194b237baa39@o115070.ingest.sentry.io/5385534"
  sentry_environment = "dev"
}

module "api_server_ingress" {
  source = "github.com/serlo/infrastructure-modules-shared.git//ingress?ref=34a6da8a720f4b8b3a381d57551f4c6bf6de1249"

  name      = "api"
  namespace = kubernetes_namespace.api_namespace.metadata.0.name
  host      = "api.${local.domain}"
  backend = {
    service_name = module.api_server.service_name
    service_port = module.api_server.service_port
  }
  enable_tls = true
}

resource "kubernetes_namespace" "api_namespace" {
  metadata {
    name = "api"
  }
}
