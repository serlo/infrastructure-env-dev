locals {
  matomo = {
    matomo_image_tag = "3.13.4"
  }
}

module "matomo" {
  source = "github.com/serlo/infrastructure-modules-shared//matomo?ref=db7232c2d87e3962293280119a507eafbc7e267f"

  app_replicas  = 1
  image_tag     = local.matomo.matomo_image_tag
  namespace     = kubernetes_namespace.matomo_namespace.metadata.0.name
  database_host = module.gcloud_mysql.database_private_ip_address
  database_user = "serlo"
  #var.matomo_mysql_password
  database_password    = var.athene2_database_password_default
  database_name        = "matomo"
  persistent_disk_name = "matomo-storage-${local.project}"
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
