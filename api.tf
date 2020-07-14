locals {
  api = {
    image_tag = "0.5.7"
  }
}

module "api_redis" {
  source = "github.com/serlo/infrastructure-modules-shared.git//redis?ref=9b7a486cf487a79069e4a0c7806de0666f78a0c4"

  namespace     = kubernetes_namespace.api_namespace.metadata.0.name
  chart_version = "10.5.7"
  image_tag     = "4.0.14"
}

module "api_secrets" {
  source = "github.com/serlo/infrastructure-modules-api.git//secrets?ref=3ad43a12c6a793738c0f2d425dc26631a3a7caaf"
}

module "api_server" {
  source = "github.com/serlo/infrastructure-modules-api.git//server?ref=3ad43a12c6a793738c0f2d425dc26631a3a7caaf"

  namespace         = kubernetes_namespace.api_namespace.metadata.0.name
  image_tag         = local.api.image_tag
  image_pull_policy = "IfNotPresent"

  secrets              = module.api_secrets
  redis_host           = "redis-master"
  hydra_host           = module.hydra.admin_uri
  serlo_org_ip_address = module.serlo_org.server_service_ip_address
}

module "api_server_ingress" {
  source = "github.com/serlo/infrastructure-modules-shared.git//ingress?ref=9b7a486cf487a79069e4a0c7806de0666f78a0c4"

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
