locals {
  api = {
    image_tag = "0.5.2"
  }
}

module "api_redis" {
  source = "github.com/serlo/infrastructure-modules-shared.git//redis?ref=35e7e47d61b4fa5a539910594398d257fb797839"

  namespace     = kubernetes_namespace.api_namespace.metadata.0.name
  chart_version = "10.5.7"
  image_tag     = "4.0.14"
}

module "api_secrets" {
  source = "github.com/serlo/infrastructure-modules-api.git//secrets?ref=03a772b0b85df65e38d82cf59494edd5389c3fdf"
}

module "api_server" {
  source = "github.com/serlo/infrastructure-modules-api.git//server?ref=03a772b0b85df65e38d82cf59494edd5389c3fdf"

  namespace         = kubernetes_namespace.api_namespace.metadata.0.name
  image_tag         = local.api.image_tag
  image_pull_policy = "IfNotPresent"

  secrets              = module.api_secrets
  redis_host           = "redis-master"
  serlo_org_ip_address = module.serlo_org.server_service_ip_address
}

module "api_server_ingress" {
  source = "github.com/serlo/infrastructure-modules-shared.git//ingress?ref=35e7e47d61b4fa5a539910594398d257fb797839"

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
