#####################################################################
# settings for dev
#####################################################################
locals {
  domain  = "serlo-development.dev"
  project = "serlo-dev"

  credentials_path = "secrets/serlo-dev-terraform-6ee61882fa66.json"
  service_account  = "terraform@serlo-dev.iam.gserviceaccount.com"
  region           = "europe-west3"

  cluster_machine_type = "n1-standard-2"

  athene2_httpd_image               = "eu.gcr.io/serlo-shared/serlo-org-httpd:3.3.3"
  athene2_php_image                 = "eu.gcr.io/serlo-shared/serlo-org-php:3.3.3"
  athene2_php_definitions-file_path = "secrets/athene2/definitions.dev.php"

  athene2_notifications-job_image = "eu.gcr.io/serlo-shared/serlo-org-notifications-job:1.0.2"

  athene2_database_instance_name = "${local.project}-mysql-instance-23072019-2"

  legacy-editor-renderer_image = "eu.gcr.io/serlo-shared/serlo-org-legacy-editor-renderer:1.0.0"
  editor-renderer_image        = "eu.gcr.io/serlo-shared/serlo-org-editor-renderer:2.0.9"

  kpi_database_instance_name = "${local.project}-postgres-instance-23072019-1"

  ingress_tls_certificate_path = "secrets/serlo_dev_selfsigned.crt"
  ingress_tls_key_path         = "secrets/serlo_dev_selfsigned.key"

  athene2_namespace = "athene2"
}

#####################################################################
# providers
#####################################################################
provider "cloudflare" {
  version = "~> 2.0"
  email   = var.cloudflare_email
  api_key = var.cloudflare_token
}

provider "google" {
  version     = "~> 2.18"
  project     = local.project
  credentials = file(local.credentials_path)
}

provider "google-beta" {
  version     = "~> 2.18"
  project     = local.project
  credentials = file(local.credentials_path)
}

provider "helm" {
  version = "~> 0.10"
  kubernetes {
    host     = module.gcloud.host
    username = ""
    password = ""

    client_certificate     = base64decode(module.gcloud.client_certificate)
    client_key             = base64decode(module.gcloud.client_key)
    cluster_ca_certificate = base64decode(module.gcloud.cluster_ca_certificate)
  }
}

provider "kubernetes" {
  version          = "~> 1.8"
  host             = module.gcloud.host
  load_config_file = false

  client_certificate     = base64decode(module.gcloud.client_certificate)
  client_key             = base64decode(module.gcloud.client_key)
  cluster_ca_certificate = base64decode(module.gcloud.cluster_ca_certificate)
}

provider "null" {
  version = "~> 2.1"
}

provider "random" {
  version = "~> 2.2"
}

provider "template" {
  version = "~> 2.1"
}

#####################################################################
# modules
#####################################################################
module "gcloud" {
  source                   = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud?ref=15666ddbd5b93c74c28781fec90a7b03b99b6377"
  project                  = local.project
  clustername              = "${local.project}-cluster"
  location                 = "europe-west3-a"
  region                   = local.region
  machine_type             = local.cluster_machine_type
  issue_client_certificate = true
  logging_service          = "logging.googleapis.com/kubernetes"
  monitoring_service       = "monitoring.googleapis.com/kubernetes"

  providers = {
    google      = "google"
    google-beta = "google-beta"
  }
}

module "gcloud_mysql" {
  source                     = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_mysql?ref=15666ddbd5b93c74c28781fec90a7b03b99b6377"
  database_instance_name     = local.athene2_database_instance_name
  database_connection_name   = "${local.project}:${local.region}:${local.athene2_database_instance_name}"
  database_region            = local.region
  database_name              = "serlo"
  database_tier              = "db-f1-micro"
  database_private_network   = module.gcloud.network
  private_ip_address_range   = module.gcloud.private_ip_address_range
  database_password_default  = var.athene2_database_password_default
  database_password_readonly = var.athene2_database_password_readonly

  providers = {
    google      = "google"
    google-beta = "google-beta"
  }
}

module "gcloud_postgres" {
  source                   = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_postgres?ref=4834fc2bb1d4de1f89d06ecc6060d0e35da10b8e"
  database_instance_name   = local.kpi_database_instance_name
  database_connection_name = "${local.project}:${local.region}:${local.kpi_database_instance_name}"
  database_region          = local.region
  database_names           = ["kpi", "hydra"]
  database_private_network = module.gcloud.network
  private_ip_address_range = module.gcloud.private_ip_address_range

  database_password_postgres = var.kpi_kpi_database_password_postgres
  database_username_default  = module.kpi.kpi_database_username_default
  database_password_default  = var.kpi_kpi_database_password_default
  database_username_readonly = module.kpi.kpi_database_username_readonly
  database_password_readonly = var.kpi_kpi_database_password_readonly

  providers = {
    google      = "google"
    google-beta = "google-beta"
  }
}

module "gcloud_dbdump_reader" {
  source = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_dbdump_reader?ref=master"

  providers = {
    google = "google"
  }
}

module "athene2_dbsetup" {
  source                      = "github.com/serlo/infrastructure-modules-serlo.org.git//athene2_dbsetup?ref=089269eaccfa66c65362fe92d014303c39f4449d"
  namespace                   = kubernetes_namespace.athene2_namespace.metadata.0.name
  database_password_default   = var.athene2_database_password_default
  database_host               = module.gcloud_mysql.database_private_ip_address
  gcloud_service_account_key  = module.gcloud_dbdump_reader.account_key
  gcloud_service_account_name = module.gcloud_dbdump_reader.account_name

  providers = {
    null       = "null"
    kubernetes = "kubernetes"
  }
}

module "athene2_metrics" {
  source = "github.com/serlo/infrastructure-modules-serlo.org.git//athene2_metrics?ref=089269eaccfa66c65362fe92d014303c39f4449d"

  providers = {
    google = "google"
  }
}

module "legacy-editor-renderer" {
  source       = "github.com/serlo/infrastructure-modules-serlo.org.git//legacy-editor-renderer?ref=089269eaccfa66c65362fe92d014303c39f4449d"
  image        = local.legacy-editor-renderer_image
  namespace    = kubernetes_namespace.athene2_namespace.metadata.0.name
  app_replicas = 1

  providers = {
    kubernetes = "kubernetes"
  }
}

module "editor-renderer" {
  source       = "github.com/serlo/infrastructure-modules-serlo.org.git//editor-renderer?ref=089269eaccfa66c65362fe92d014303c39f4449d"
  image        = local.editor-renderer_image
  namespace    = kubernetes_namespace.athene2_namespace.metadata.0.name
  app_replicas = 1

  providers = {
    kubernetes = "kubernetes"
  }
}

module "varnish" {
  source         = "github.com/serlo/infrastructure-modules-shared.git//varnish?ref=339bb895e858277b4cb790b285a0004cc7d6450b"
  namespace      = kubernetes_namespace.athene2_namespace.metadata.0.name
  app_replicas   = 1
  image          = "eu.gcr.io/serlo-shared/varnish:6.0.2"
  varnish_memory = "100M"
  backend_ip     = module.athene2.service_name

  resources_limits_cpu      = "50m"
  resources_limits_memory   = "100Mi"
  resources_requests_cpu    = "50m"
  resources_requests_memory = "100Mi"

  providers = {
    kubernetes = "kubernetes"
    template   = "template"
  }
}

module "athene2" {
  source = "github.com/serlo/infrastructure-modules-serlo.org.git//server?ref=85ebee63c7c503b0006a9d18642360a0cc4817fd"

  php_definitions-file_path = local.athene2_php_definitions-file_path
  php_recaptcha_key         = var.athene2_php_recaptcha_key
  php_recaptcha_secret      = var.athene2_php_recaptcha_secret
  php_smtp_password         = var.athene2_php_smtp_password
  php_newsletter_key        = var.athene2_php_newsletter_key
  php_tracking_switch       = var.athene2_php_tracking_switch

  database_username_default  = "serlo"
  database_username_readonly = "serlo_readonly"
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
  hydra_uri                  = module.hydra.admin_uri

  enable_basic_auth = true
  enable_cronjobs   = true
  enable_mail_mock  = true

  providers = {
    kubernetes = "kubernetes"
    random     = "random"
    template   = "template"
  }
  feature_flags     = "[]"
  image_pull_policy = "Always"
  images = {
    httpd             = local.athene2_httpd_image
    php               = local.athene2_php_image
    notifications_job = local.athene2_notifications-job_image
  }
  namespace = kubernetes_namespace.athene2_namespace.metadata.0.name
}

module "kpi_metrics" {
  source = "github.com/serlo/infrastructure-modules-kpi.git//kpi_metrics?ref=master"
  providers = {
    google = "google"
  }
}

module "kpi" {
  source = "github.com/serlo/infrastructure-modules-kpi.git//kpi?ref=v1.3.0"
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

  providers = {
    kubernetes = "kubernetes"
  }
}

module "ingress-nginx" {
  source               = "github.com/serlo/infrastructure-modules-shared.git//ingress-nginx?ref=339bb895e858277b4cb790b285a0004cc7d6450b"
  namespace            = kubernetes_namespace.ingress_nginx_namespace.metadata.0.name
  ip                   = module.gcloud.staticip_regional_address
  nginx_image          = "quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.24.1"
  tls_certificate_path = local.ingress_tls_certificate_path
  tls_key_path         = local.ingress_tls_key_path

  providers = {
    kubernetes = "kubernetes"
  }
}

module "cloudflare" {
  source  = "github.com/serlo/infrastructure-modules-env-shared.git//cloudflare?ref=36d906c2b2a665836714babc9cdd7d4c7a2b5143"
  domain  = local.domain
  ip      = module.gcloud.staticip_regional_address
  zone_id = "1064522c8625cd2973a8a61910106e01"

  providers = {
    cloudflare = "cloudflare"
  }
}

module "hydra" {
  source               = "github.com/serlo/infrastructure-modules-shared.git//hydra?ref=fc5434ebfea25af2996ab976ba7a5f75fa21da1c"
  dsn                  = "postgres://${module.kpi.kpi_database_username_default}:${var.kpi_kpi_database_password_default}@${module.gcloud_postgres.database_private_ip_address}/hydra"
  url_login            = "https://de.${local.domain}/auth/hydra/login"
  url_consent          = "https://de.${local.domain}/auth/hydra/consent"
  host                 = "hydra.${local.domain}"
  namespace            = kubernetes_namespace.hydra_namespace.metadata.0.name
  salt                 = "1234567890123456789"
  tls_certificate_path = "secrets/hydra_selfsigned.crt"
  tls_key_path         = "secrets/hydra_selfsigned.key"

  providers = {
    helm       = "helm"
    kubernetes = "kubernetes"
    random     = "random"
    template   = "template"
  }
}

module "rocket-chat" {
  source    = "github.com/serlo/infrastructure-modules-shared.git//rocket-chat?ref=fc5434ebfea25af2996ab976ba7a5f75fa21da1c"
  host      = "community.${local.domain}"
  namespace = kubernetes_namespace.community_namespace.metadata.0.name

  providers = {
    helm = "helm"
  }
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
      service_name = module.varnish.service_name
      service_port = module.varnish.service_port
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
    name = local.athene2_namespace
  }
}

resource "kubernetes_namespace" "kpi_namespace" {
  metadata {
    name = "kpi"
  }
}

resource "kubernetes_namespace" "community_namespace" {
  metadata {
    name = "community"
  }
}

resource "kubernetes_namespace" "hydra_namespace" {
  metadata {
    name = "hydra"
  }
}

resource "kubernetes_namespace" "ingress_nginx_namespace" {
  metadata {
    name = "ingress-nginx"
  }
}
