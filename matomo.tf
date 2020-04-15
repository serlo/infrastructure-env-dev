locals {
  matomo = {
    matomo_image_tag = "3.13.3"
  }
}

module "matomo" {
  source = "github.com/serlo/infrastructure-modules-shared//matomo?ref=e437225079eca76bfe52a200a2f7a1590744ef59"

  app_replicas  = 1
  image_tag     = local.matomo.matomo_image_tag
  namespace     = kubernetes_namespace.matomo_namespace.metadata.0.name
  database_host = module.gcloud_mysql.database_private_ip_address
  database_user = "serlo"
  #var.matomo_mysql_password
  database_password = var.athene2_database_password_default
  database_name     = "matomo"
}

resource "kubernetes_namespace" "matomo_namespace" {
  metadata {
    name = "matomo"
  }
}

module "matomo_ingress" {
  source = "github.com/serlo/infrastructure-modules-shared.git//ingress?ref=c41476e253475fa2eacbada4228074dd6d7df58f"

  name      = "matomo"
  namespace = kubernetes_namespace.matomo_namespace.metadata.0.name
  host      = "analytics.${local.domain}"
  backend = {
    service_name = module.matomo.matomo_service_name
    service_port = module.matomo.matomo_service_port
  }
  enable_tls = true
}
