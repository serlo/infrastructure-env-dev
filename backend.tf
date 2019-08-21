terraform {
  backend "gcs" {
    bucket      = "serlo_dev_terraform"
    prefix      = "state"
    credentials = "secrets/serlo-dev-terraform-6ee61882fa66.json"
  }
}
