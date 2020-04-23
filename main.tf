#####################################################################
# settings for dev
#####################################################################
locals {
  domain  = "serlo-development.dev"
  project = "serlo-dev"

  credentials_path = "secrets/serlo-dev-terraform-6ee61882fa66.json"
  service_account  = "terraform@serlo-dev.iam.gserviceaccount.com"

  region = "europe-west3"
  zone   = "europe-west3-a"

  cluster_machine_type = "n1-highcpu-2"

  athene2_database_instance_name = "${local.project}-mysql-2020-01-19-1"
  kpi_database_instance_name     = "${local.project}-postgres-2020-01-19-1"
}

#####################################################################
# modules
#####################################################################
module "cluster" {
  source   = "github.com/serlo/infrastructure-modules-gcloud.git//cluster?ref=eac9c2757582cc3483310fa8649fa43904cb3c6b"
  name     = "${local.project}-cluster"
  location = local.zone
  region   = local.region

  node_pool = {
    machine_type       = local.cluster_machine_type
    preemptible        = true
    initial_node_count = 2
    min_node_count     = 2
    max_node_count     = 10
  }
}

module "gcloud_mysql" {
  source                     = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_mysql?ref=eac9c2757582cc3483310fa8649fa43904cb3c6b"
  database_instance_name     = local.athene2_database_instance_name
  database_connection_name   = "${local.project}:${local.region}:${local.athene2_database_instance_name}"
  database_region            = local.region
  database_name              = "serlo"
  database_tier              = "db-f1-micro"
  database_private_network   = module.cluster.network
  database_password_default  = var.athene2_database_password_default
  database_password_readonly = var.athene2_database_password_readonly
}

module "gcloud_postgres" {
  source                   = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_postgres?ref=eac9c2757582cc3483310fa8649fa43904cb3c6b"
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
}

module "gcloud_dbdump_reader" {
  source = "github.com/serlo/infrastructure-modules-gcloud.git//gcloud_dbdump_reader?ref=eac9c2757582cc3483310fa8649fa43904cb3c6b"
}

module "athene2_dbsetup" {
  source                      = "github.com/serlo/infrastructure-modules-serlo.org.git//athene2_dbsetup?ref=c878e860fa48c337a6d1a40ee21c983f26a39dfa"
  namespace                   = kubernetes_namespace.serlo_org_namespace.metadata.0.name
  database_password_default   = var.athene2_database_password_default
  database_host               = module.gcloud_mysql.database_private_ip_address
  gcloud_service_account_key  = module.gcloud_dbdump_reader.account_key
  gcloud_service_account_name = module.gcloud_dbdump_reader.account_name
  dbsetup_image               = "eu.gcr.io/serlo-shared/athene2-dbsetup-cronjob:2.0.1"
}

module "ingress-nginx" {
  source = "github.com/serlo/infrastructure-modules-shared.git//ingress-nginx?ref=d3bffe9d351f6b466636bf2ac6bdb27c8730fd31"

  namespace   = kubernetes_namespace.ingress_nginx_namespace.metadata.0.name
  ip          = module.cluster.address
  domain      = "*.${local.domain}"
  nginx_image = "quay.io/kubernetes-ingress-controller/nginx-ingress-controller:0.24.1"
}

module "cloudflare" {
  source  = "github.com/serlo/infrastructure-modules-env-shared.git//cloudflare?ref=ac5cbca76483550d193910b9732644bc48ed345b"
  domain  = local.domain
  ip      = module.cluster.address
  zone_id = "cedde9a4ab2980cd92bfc3765dc2e475"
}

#####################################################################
# namespaces
#####################################################################
resource "kubernetes_namespace" "ingress_nginx_namespace" {
  metadata {
    name = "ingress-nginx"
  }
}
