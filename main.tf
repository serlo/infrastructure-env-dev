#####################################################################
# settings for dev
#####################################################################
locals {
  domain  = "serlo-development.dev"
  project = "serlo-dev"

  credentials_path = "secrets/serlo-dev-terraform-6ee61882fa66.json"
  service_account  = "terraform@serlo-dev.iam.gserviceaccount.com"

  region = "europe-west3"

  cluster_machine_type = "n1-standard-2"

  athene2_httpd_image               = "eu.gcr.io/serlo-shared/serlo-org-httpd:1.1.3"
  athene2_php_image                 = "eu.gcr.io/serlo-shared/serlo-org-php:1.1.3"
  athene2_php_definitions-file_path = "secrets/athene2/definitions.dev.php"
  cloudsql_credentials_path         = "secrets/serlo-dev-cloudsql-421bf4612759.json"

  athene2_notifications-job_image = "eu.gcr.io/serlo-shared/serlo-org-notifications-job:1.0.2"

  athene2_database_instance_name = "${local.project}-mysql-instance-23072019-2"
  kpi_database_instance_name     = "${local.project}-postgres-instance-23072019-1"
  kpi_database_username_default  = "serlo"
  kpi_database_username_readonly = "serlo_readonly"

  legacy-editor-renderer_image = "eu.gcr.io/serlo-shared/legacy-editor-renderer:latest"
  editor-renderer_image        = "eu.gcr.io/serlo-shared/editor-renderer:latest"

  ingress_tls_certificate_path = "secrets/serlo_dev_selfsigned.crt"
  ingress_tls_key_path         = "secrets/serlo_dev_selfsigned.key"
}

#####################################################################
# providers
#####################################################################
provider "google" {
  project     = "${local.project}"
  credentials = "${file("${local.credentials_path}")}"
}

provider "google-beta" {
  project     = "${local.project}"
  credentials = "${file("${local.credentials_path}")}"
}

provider "kubernetes" {
  version          = "~> 1.8"
  host             = "${module.gcloud.host}"
  load_config_file = false

  client_certificate     = base64decode(module.gcloud.client_certificate)
  client_key             = base64decode(module.gcloud.client_key)
  cluster_ca_certificate = base64decode(module.gcloud.cluster_ca_certificate)
}

provider "cloudflare" {
  email = var.cloudflare_email
  token = var.cloudflare_token
}

provider "template" {}

#####################################################################
# modules
#####################################################################
module "gcloud" {
  source                   = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud?ref=master"
  project                  = local.project
  clustername              = "${local.project}-cluster"
  zone                     = "europe-west3-a"
  region                   = local.region
  machine_type             = local.cluster_machine_type
  issue_client_certificate = true
  logging_service          = "logging.googleapis.com/kubernetes"
  monitoring_service       = "monitoring.googleapis.com/kubernetes"
}

module "gcloud_mysql" {
  source                     = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_mysql?ref=master"
  database_instance_name     = local.athene2_database_instance_name
  database_connection_name   = "${local.project}:${local.region}:${local.athene2_database_instance_name}"
  database_region            = local.region
  database_private_network   = module.gcloud.network
  private_ip_address_range   = module.gcloud.private_ip_address_range
  database_name              = "serlo"
  database_password_default  = var.athene2_database_password_default
  database_password_readonly = var.athene2_database_password_readonly
}

module "gcloud_postgres" {
  source                     = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_postgres?ref=master"
  database_instance_name     = local.kpi_database_instance_name
  database_connection_name   = "${local.project}:${local.region}:${local.kpi_database_instance_name}"
  database_region            = local.region
  database_private_network   = module.gcloud.network
  private_ip_address_range   = module.gcloud.private_ip_address_range
  database_name              = module.kpi.kpi_database_name
  database_password_postgres = var.kpi_kpi_database_password_postgres
  database_username_default  = local.kpi_database_username_default
  database_password_default  = var.kpi_kpi_database_password_default
  database_username_readonly = local.kpi_database_username_readonly
  database_password_readonly = var.kpi_kpi_database_password_readonly
}

module "gcloud_dbdump_reader" {
  source = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_dbdump_reader?ref=master"
}

module "athene2_dbsetup" {
  source                      = "github.com/serlo/infrastructure-modules-serlo.org.git//athene2_dbsetup?ref=master"
  namespace                   = kubernetes_namespace.athene2_namespace.metadata.0.name
  database_password_default   = var.athene2_database_password_default
  database_host               = module.gcloud_mysql.database_private_ip_address
  gcloud_service_account_key  = module.gcloud_dbdump_reader.account_key
  gcloud_service_account_name = module.gcloud_dbdump_reader.account_name
}

module "gcloud_dbdump_writer" {
  source = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_dbdump_writer?ref=master"
}

module "athene2_dbdump" {
  source                      = "github.com/serlo/infrastructure-modules-serlo.org.git//athene2_dbdump?ref=master"
  namespace                   = kubernetes_namespace.athene2_namespace.metadata.0.name
  database_password_readonly  = var.athene2_database_password_readonly
  database_host               = module.gcloud_mysql.database_private_ip_address
  gcloud_service_account_key  = module.gcloud_dbdump_writer.account_key
  gcloud_service_account_name = module.gcloud_dbdump_writer.account_name
  gcloud_bucket_url           = "gs://anonymous-data/serlo-dev"
}

module "athene2_metrics" {
  source = "github.com/serlo/infrastructure-modules-serlo.org.git//athene2_metrics?ref=master"
}

module "legacy-editor-renderer" {
  source       = "github.com/serlo/infrastructure-modules-serlo.org.git//legacy-editor-renderer?ref=master"
  image        = local.legacy-editor-renderer_image
  namespace    = kubernetes_namespace.athene2_namespace.metadata.0.name
  app_replicas = 1
}

module "editor-renderer" {
  source       = "github.com/serlo/infrastructure-modules-serlo.org.git//editor-renderer?ref=master"
  image        = local.editor-renderer_image
  namespace    = kubernetes_namespace.athene2_namespace.metadata.0.name
  app_replicas = 1
}

module "varnish" {
  source         = "github.com/serlo/infrastructure-modules-shared.git//varnish?ref=master"
  namespace      = kubernetes_namespace.athene2_namespace.metadata.0.name
  app_replicas   = 1
  image          = "eu.gcr.io/serlo-shared/varnish:latest"
  backend_ip     = module.athene2.athene2_service_ip
  varnish_memory = "100M"

  resources_limits_cpu      = "50m"
  resources_limits_memory   = "100Mi"
  resources_requests_cpu    = "50m"
  resources_requests_memory = "100Mi"
}

module "athene2" {
  source                  = "github.com/serlo/infrastructure-modules-serlo.org.git//athene2?ref=master"
  httpd_image             = local.athene2_httpd_image
  notifications-job_image = local.athene2_notifications-job_image

  php_image                 = local.athene2_php_image
  php_definitions-file_path = local.athene2_php_definitions-file_path
  php_recaptcha_key         = var.athene2_php_recaptcha_key
  php_recaptcha_secret      = var.athene2_php_recaptcha_secret
  php_smtp_password         = var.athene2_php_smtp_password
  php_newsletter_key        = var.athene2_php_newsletter_key
  php_tracking_switch       = var.athene2_php_tracking_switch

  database_password_default  = var.athene2_database_password_default
  database_password_readonly = var.athene2_database_password_readonly
  database_private_ip        = module.gcloud_mysql.database_private_ip_address

  app_replicas = 1

  httpd_container_limits_cpu      = "200m"
  httpd_container_limits_memory   = "200Mi"
  httpd_container_requests_cpu    = "100m"
  httpd_container_requests_memory = "100Mi"

  php_container_limits_cpu      = "700m"
  php_container_limits_memory   = "600Mi"
  php_container_requests_cpu    = "400m"
  php_container_requests_memory = "200Mi"

  domain = local.domain

  upload_secret = file("secrets/serlo-org-6bab84a1b1a5.json")

  legacy_editor_renderer_uri = module.legacy-editor-renderer.service_uri
  editor_renderer_uri        = module.editor-renderer.service_uri

  enable_basic_auth = true
  enable_cronjobs   = true
  enable_mail_mock  = true
}

module "kpi_metrics" {
  source = "github.com/serlo/infrastructure-modules-kpi.git//kpi_metrics?ref=master"
}

module "kpi" {
  source = "github.com/serlo/infrastructure-modules-kpi.git//kpi?ref=v1.1.0"
  domain = local.domain

  grafana_admin_password = var.kpi_grafana_admin_password
  grafana_serlo_password = var.kpi_grafana_serlo_password

  athene2_database_host              = module.gcloud_mysql.database_private_ip_address
  athene2_database_password_readonly = var.athene2_database_password_readonly

  kpi_database_host              = module.gcloud_postgres.database_private_ip_address
  kpi_database_password_default  = var.kpi_kpi_database_password_default
  kpi_database_password_readonly = var.kpi_kpi_database_password_readonly

  grafana_image        = "eu.gcr.io/serlo-shared/kpi-grafana:1.0.1"
  mysql_importer_image = "eu.gcr.io/serlo-shared/kpi-mysql-importer:1.2.1"
  aggregator_image     = "eu.gcr.io/serlo-shared/kpi-aggregator:1.3.2"
}

module "ingress-nginx" {
  source               = "github.com/serlo/infrastructure-modules-shared.git//ingress-nginx?ref=master"
  namespace            = kubernetes_namespace.ingress_nginx_namespace.metadata.0.name
  ip                   = module.gcloud.staticip_regional_address
  nginx_image          = "quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.24.1"
  tls_certificate_path = local.ingress_tls_certificate_path
  tls_key_path         = local.ingress_tls_key_path
}

module "cloudflare" {
  source = "github.com/serlo/infrastructure-modules-env-shared.git//cloudflare?ref=master"
  domain = local.domain
  ip     = module.gcloud.staticip_regional_address
}

#####################################################################
# ingress
#####################################################################

resource "kubernetes_ingress" "kpi_ingress" {
  metadata {
    name      = "kpi-ingress"
    namespace = kubernetes_namespace.kpi_namespace.metadata.0.name

    annotations = {
      "kubernetes.io/ingress.class" = "nginx"
    }
  }

  spec {
    rule {
      host = "stats.${local.domain}"

      http {
        path {
          path = "/"

          backend {
            service_name = module.kpi.grafana_service_name
            service_port = module.kpi.grafana_service_port
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress" "athene2_ingress" {
  metadata {
    name      = "athene2-ingress"
    namespace = kubernetes_namespace.athene2_namespace.metadata.0.name

    annotations = { "kubernetes.io/ingress.class" = "nginx",
      "nginx.ingress.kubernetes.io/auth-type"   = "basic",
      "nginx.ingress.kubernetes.io/auth-secret" = "basic-auth-ingress-secret",
      "nginx.ingress.kubernetes.io/auth-realm"  = "Authentication Required"
    }

  }

  spec {
    backend {
      service_name = module.varnish.varnish_service_name
      service_port = module.varnish.varnish_service_port
    }
  }
}

resource "kubernetes_secret" "basic_auth_ingress_secret" {

  metadata {
    name      = "basic-auth-ingress-secret"
    namespace = kubernetes_namespace.athene2_namespace.metadata.0.name
  }

  data = {
    auth = "serloteam:$apr1$L6BuktMk$qfh8xvsWsPi3uXB0fIiu1/"
  }
}


#####################################################################
# namespaces
#####################################################################
resource "kubernetes_namespace" "athene2_namespace" {
  metadata {
    name = "athene2"
  }
}

resource "kubernetes_namespace" "kpi_namespace" {
  metadata {
    name = "kpi"
  }
}

resource "kubernetes_namespace" "ingress_nginx_namespace" {
  metadata {
    name = "ingress-nginx"
  }
}
