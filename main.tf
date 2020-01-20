#####################################################################
# settings for dev
#####################################################################
locals {
  domain  = "serlo-development.dev"
  project = "serlo-dev"

  credentials_path = "secrets/serlo-dev-terraform-6ee61882fa66.json"
  service_account  = "terraform@serlo-dev.iam.gserviceaccount.com"
  region           = "europe-west3"

  cluster_machine_type = "n1-standard-1"

  serlo_org_image_tags = {
    server = {
      httpd             = "5.2.4"
      php               = "5.2.4"
      notifications_job = "2.0.1"
    }
    editor_renderer        = "4.0.4"
    legacy_editor_renderer = "2.0.0"
    frontend               = "2.0.8"
  }
  varnish_image = "eu.gcr.io/serlo-shared/varnish:6.0"

  athene2_php_definitions-file_path = "secrets/athene2/definitions.dev.php"

  athene2_database_instance_name = "${local.project}-mysql-2020-01-19-1"
  kpi_database_instance_name     = "${local.project}-postgres-2020-01-19-1"
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
    host     = module.cluster.endpoint
    username = ""
    password = ""

    client_certificate     = base64decode(module.cluster.auth.client_certificate)
    client_key             = base64decode(module.cluster.auth.client_key)
    cluster_ca_certificate = base64decode(module.cluster.auth.cluster_ca_certificate)
  }
}

provider "kubernetes" {
  version          = "~> 1.8"
  host             = module.cluster.endpoint
  load_config_file = false

  client_certificate     = base64decode(module.cluster.auth.client_certificate)
  client_key             = base64decode(module.cluster.auth.client_key)
  cluster_ca_certificate = base64decode(module.cluster.auth.cluster_ca_certificate)
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

provider "tls" {
  version = "~> 2.1"
}

#####################################################################
# modules
#####################################################################
module "cluster" {
  source   = "github.com/serlo/infrastructure-modules-gcloud.git//cluster?ref=db007789fd2c69457034b29ab95f30ac5ffe2e7d"
  name     = "${local.project}-cluster"
  location = "europe-west3-a"
  region   = local.region

  node_pool = {
    machine_type       = local.cluster_machine_type
    preemptible        = true
    initial_node_count = 2
    min_node_count     = 2
    max_node_count     = 10
  }

  providers = {
    google      = google
    google-beta = google-beta
  }
}

module "gcloud_mysql" {
  source                     = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_mysql?ref=db007789fd2c69457034b29ab95f30ac5ffe2e7d"
  database_instance_name     = local.athene2_database_instance_name
  database_connection_name   = "${local.project}:${local.region}:${local.athene2_database_instance_name}"
  database_region            = local.region
  database_name              = "serlo"
  database_tier              = "db-f1-micro"
  database_private_network   = module.cluster.network
  database_password_default  = var.athene2_database_password_default
  database_password_readonly = var.athene2_database_password_readonly

  providers = {
    google      = google
    google-beta = google-beta
  }
}

module "gcloud_postgres" {
  source                   = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_postgres?ref=db007789fd2c69457034b29ab95f30ac5ffe2e7d"
  database_instance_name   = local.kpi_database_instance_name
  database_connection_name = "${local.project}:${local.region}:${local.kpi_database_instance_name}"
  database_region          = local.region
  database_names           = ["kpi", "hydra"]
  database_private_network = module.cluster.network

  database_password_postgres = var.kpi_kpi_database_password_postgres
  database_username_default  = module.kpi.kpi_database_username_default
  database_password_default  = var.kpi_kpi_database_password_default
  database_username_readonly = module.kpi.kpi_database_username_readonly
  database_password_readonly = var.kpi_kpi_database_password_readonly

  providers = {
    google      = google
    google-beta = google-beta
  }
}

module "serlo_org" {
  source = "github.com/serlo/infrastructure-modules-serlo.org.git//?ref=fb43d20a82d2cf2345392a1f2de2020165098ffe"

  namespace         = kubernetes_namespace.serlo_org_namespace.metadata.0.name
  image_pull_policy = "IfNotPresent"

  server = {
    app_replicas = 1
    image_tags   = local.serlo_org_image_tags.server

    domain                = local.domain
    definitions_file_path = local.athene2_php_definitions-file_path

    resources = {
      httpd = {
        limits = {
          cpu    = "200m"
          memory = "200Mi"
        }
        requests = {
          cpu    = "100m"
          memory = "100Mi"
        }
      }
      php = {
        limits = {
          cpu    = "700m"
          memory = "600Mi"
        }
        requests = {
          cpu    = "400m"
          memory = "200Mi"
        }
      }
    }

    recaptcha = {
      key    = var.athene2_php_recaptcha_key
      secret = var.athene2_php_recaptcha_secret
    }

    smtp_password = var.athene2_php_smtp_password
    mailchimp_key = var.athene2_php_newsletter_key

    enable_tracking   = var.athene2_php_tracking_switch
    enable_basic_auth = true
    enable_cronjobs   = true
    enable_mail_mock  = true

    database = {
      host     = module.gcloud_mysql.database_private_ip_address
      username = "serlo"
      password = var.athene2_database_password_default
    }

    database_readonly = {
      username = "serlo_readonly"
      password = var.athene2_database_password_readonly
    }

    upload_secret   = file("secrets/serlo-org-6bab84a1b1a5.json")
    hydra_admin_uri = module.hydra.admin_uri
    feature_flags   = "['client-frontend' => true, 'frontend-content' => true, 'frontend-diff' => true, 'frontend-editor' => true, 'frontend-footer' => true, 'frontend-legacy-content' => true, 'key-value-store' => true]"
    redis_hosts     = "['redis-master.redis']"
  }

  editor_renderer = {
    app_replicas = 1
    image_tag    = local.serlo_org_image_tags.editor_renderer
  }

  legacy_editor_renderer = {
    app_replicas = 1
    image_tag    = local.serlo_org_image_tags.legacy_editor_renderer
  }

  frontend = {
    app_replicas = 1
    image_tag    = local.serlo_org_image_tags.frontend
  }

  varnish = {
    app_replicas = 1
    image        = local.varnish_image
    memory       = "100M"
  }

  providers = {
    kubernetes = kubernetes
    random     = random
    template   = template
  }
}

module "gcloud_dbdump_reader" {
  source = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_dbdump_reader?ref=db007789fd2c69457034b29ab95f30ac5ffe2e7d"

  providers = {
    google = google
  }
}

module "athene2_dbsetup" {
  source                      = "github.com/serlo/infrastructure-modules-serlo.org.git//athene2_dbsetup?ref=fb43d20a82d2cf2345392a1f2de2020165098ffe"
  namespace                   = kubernetes_namespace.serlo_org_namespace.metadata.0.name
  database_password_default   = var.athene2_database_password_default
  database_host               = module.gcloud_mysql.database_private_ip_address
  gcloud_service_account_key  = module.gcloud_dbdump_reader.account_key
  gcloud_service_account_name = module.gcloud_dbdump_reader.account_name
  dbsetup_image               = "eu.gcr.io/serlo-shared/athene2-dbsetup-cronjob:1.3.2"

  providers = {
    null       = null
    kubernetes = kubernetes
  }
}

module "athene2_metrics" {
  source = "github.com/serlo/infrastructure-modules-serlo.org.git//athene2_metrics?ref=fb43d20a82d2cf2345392a1f2de2020165098ffe"

  providers = {
    google = google
  }
}

module "kpi_metrics" {
  source = "github.com/serlo/infrastructure-modules-kpi.git//kpi_metrics?ref=master"
  providers = {
    google = google
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

  grafana_image        = "eu.gcr.io/serlo-shared/kpi-grafana:1.2.0"
  mysql_importer_image = "eu.gcr.io/serlo-shared/kpi-mysql-importer:1.3.3"
  aggregator_image     = "eu.gcr.io/serlo-shared/kpi-aggregator:1.5.0"

  providers = {
    kubernetes = kubernetes
  }
}

module "ingress-nginx" {
  source      = "github.com/serlo/infrastructure-modules-shared.git//ingress-nginx?ref=c331726b68a536449f88960458c6cb4297d6be46"
  namespace   = kubernetes_namespace.ingress_nginx_namespace.metadata.0.name
  ip          = module.cluster.address
  domain      = "*.${local.domain}"
  nginx_image = "quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.24.1"

  providers = {
    kubernetes = kubernetes
    tls        = tls
  }
}

module "cloudflare" {
  source  = "github.com/serlo/infrastructure-modules-env-shared.git//cloudflare?ref=5175dfff7cc6a52d85cc66ae8c690c67f5539200"
  domain  = local.domain
  ip      = module.cluster.address
  zone_id = "1064522c8625cd2973a8a61910106e01"

  providers = {
    cloudflare = cloudflare
  }
}

module "hydra" {
  source      = "github.com/serlo/infrastructure-modules-shared.git//hydra?ref=c331726b68a536449f88960458c6cb4297d6be46"
  dsn         = "postgres://${module.kpi.kpi_database_username_default}:${var.kpi_kpi_database_password_default}@${module.gcloud_postgres.database_private_ip_address}/hydra"
  url_login   = "https://de.${local.domain}/auth/hydra/login"
  url_consent = "https://de.${local.domain}/auth/hydra/consent"
  host        = "hydra.${local.domain}"
  namespace   = kubernetes_namespace.hydra_namespace.metadata.0.name

  providers = {
    helm       = helm
    kubernetes = kubernetes
    random     = random
    template   = template
    tls        = tls
  }
}

module "redis" {
  source    = "github.com/serlo/infrastructure-modules-shared.git//redis?ref=c331726b68a536449f88960458c6cb4297d6be46"
  namespace = kubernetes_namespace.redis_namespace.metadata.0.name
  image_tag = "5.0.7-debian-9-r12"

  providers = {
    helm = helm
  }
}

#module "rocket-chat" {
#  source = "github.com/serlo/infrastructure-modules-shared.git//rocket-chat?ref=c331726b68a536449f88960458c6cb4297d6be46"
#
#  host      = "community.${local.domain}"
#  namespace = kubernetes_namespace.community_namespace.metadata.0.name
#  image_tag = "2.2.1"
#
#  mongodump = {
#    image         = "eu.gcr.io/serlo-shared/mongodb-tools-base:1.0.1"
#    schedule      = "0 0 * * *"
#    bucket_prefix = local.project
#  }
#
#  smtp_password = var.athene2_php_smtp_password
#
#  providers = {
#    google     = google
#    helm       = helm
#    kubernetes = kubernetes
#    random     = random
#    template   = template
#  }
#}

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
    namespace = kubernetes_namespace.serlo_org_namespace.metadata.0.name

    annotations = {
      "kubernetes.io/ingress.class"             = "nginx",
      "nginx.ingress.kubernetes.io/auth-type"   = "basic",
      "nginx.ingress.kubernetes.io/auth-secret" = "basic-auth-ingress-secret",
      "nginx.ingress.kubernetes.io/auth-realm"  = "Authentication Required"
    }

  }

  spec {
    backend {
      service_name = module.serlo_org.service_name
      service_port = module.serlo_org.service_port
    }
  }
}

resource "kubernetes_secret" "basic_auth_ingress_secret" {

  metadata {
    name      = "basic-auth-ingress-secret"
    namespace = kubernetes_namespace.serlo_org_namespace.metadata.0.name
  }

  data = {
    auth = "serloteam:$apr1$L6BuktMk$qfh8xvsWsPi3uXB0fIiu1/"
  }
}


#####################################################################
# namespaces
#####################################################################
resource "kubernetes_namespace" "serlo_org_namespace" {
  metadata {
    name = "serlo-org"
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

resource "kubernetes_namespace" "redis_namespace" {
  metadata {
    name = "redis"
  }
}
