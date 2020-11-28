locals {
  serlo_org = {
    image_tags = {
      server = {
        httpd             = "15.2.0"
        php               = "15.2.0"
        migrate           = "15.2.0"
        notifications_job = "3.0.1"
      }
      editor_renderer        = "11.0.2"
      legacy_editor_renderer = "3.0.1"
      varnish                = "6.0.2"
    }
  }
}

module "serlo_org" {
  source = "github.com/serlo/infrastructure-modules-serlo.org.git//?ref=777314d6f13f4877b056421c71069838bafff679"

  namespace         = kubernetes_namespace.serlo_org_namespace.metadata.0.name
  image_pull_policy = "IfNotPresent"

  server = {
    app_replicas = 1
    image_tags   = local.serlo_org.image_tags.server

    domain = local.domain

    recaptcha = {
      key    = var.athene2_php_recaptcha_key
      secret = var.athene2_php_recaptcha_secret
    }

    smtp_password = var.athene2_php_smtp_password
    mailchimp_key = var.athene2_php_newsletter_key

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

    upload_secret                = file("secrets/serlo-org-6bab84a1b1a5.json")
    hydra_admin_uri              = module.hydra.admin_uri
    feature_flags                = "[]"
    autoreview_taxonomy_term_ids = "[106082]"

    api = {
      host   = module.api_server.host
      secret = module.api_secrets.serlo_org
    }

    enable_tracking_hotjar           = false
    enable_tracking_google_analytics = false
    enable_tracking_simple_analytics = false
    enable_tracking_matomo           = false
    matomo_tracking_domain           = "analytics.${local.domain}"
  }

  editor_renderer = {
    image_tag = local.serlo_org.image_tags.editor_renderer
  }

  legacy_editor_renderer = {
    image_tag = local.serlo_org.image_tags.legacy_editor_renderer
  }

  varnish = {
    image_tag = local.serlo_org.image_tags.varnish
  }
}

module "serlo_org_metrics" {
  source = "github.com/serlo/infrastructure-modules-serlo.org.git//athene2_metrics?ref=777314d6f13f4877b056421c71069838bafff679"
}

resource "kubernetes_ingress" "athene2_ingress" {
  metadata {
    name      = "athene2-ingress"
    namespace = kubernetes_namespace.serlo_org_namespace.metadata.0.name

    annotations = {
      "kubernetes.io/ingress.class"                 = "nginx",
      "nginx.ingress.kubernetes.io/auth-type"       = "basic",
      "nginx.ingress.kubernetes.io/auth-secret"     = "basic-auth-ingress-secret",
      "nginx.ingress.kubernetes.io/auth-realm"      = "Authentication Required"
      "nginx.ingress.kubernetes.io/proxy-body-size" = "2M"
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

resource "kubernetes_namespace" "serlo_org_namespace" {
  metadata {
    name = "serlo-org"
  }
}
