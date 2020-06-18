locals {
  kpi = {
    grafana_image_tag        = "1.5.0"
    mysql_importer_image_tag = "1.4.1"
    aggregator_image_tag     = "1.6.4"
  }
}

module "kpi" {
  source = "github.com/serlo/infrastructure-modules-kpi.git//kpi?ref=v1.3.1"

  domain = local.domain

  grafana_admin_password = var.kpi_grafana_admin_password
  grafana_serlo_password = var.kpi_grafana_serlo_password

  athene2_database_host              = module.gcloud_mysql.database_private_ip_address
  athene2_database_password_readonly = var.athene2_database_password_readonly

  kpi_database_host              = module.gcloud_postgres.database_private_ip_address
  kpi_database_password_default  = var.kpi_kpi_database_password_default
  kpi_database_password_readonly = var.kpi_kpi_database_password_readonly

  grafana_image        = "eu.gcr.io/serlo-shared/kpi-grafana:${local.kpi.grafana_image_tag}"
  mysql_importer_image = "eu.gcr.io/serlo-shared/kpi-mysql-importer:${local.kpi.mysql_importer_image_tag}"
  aggregator_image     = "eu.gcr.io/serlo-shared/kpi-aggregator:${local.kpi.aggregator_image_tag}"
}

module "kpi_metrics" {
  source = "github.com/serlo/infrastructure-modules-kpi.git//kpi_metrics?ref=v1.3.1"
}

module "kpi_ingress" {
  source = "github.com/serlo/infrastructure-modules-shared.git//ingress?ref=35e7e47d61b4fa5a539910594398d257fb797839"

  name      = "kpi"
  namespace = kubernetes_namespace.kpi_namespace.metadata.0.name
  host      = "stats.${local.domain}"
  backend = {
    service_name = module.kpi.grafana_service_name
    service_port = module.kpi.grafana_service_port
  }
  enable_tls = true
}

resource "kubernetes_namespace" "kpi_namespace" {
  metadata {
    name = "kpi"
  }
}
