#
# Purpose:
#   ease the bootstraping and hide some terraform magic
#

cloudsql_credential_filename = serlo-dev-cloudsql-421bf4612759.json
export env_name = dev
export gcloud_env_name = serlo_dev
export mysql_instance=24062019-2
export postgres_instance=24062019-2

include mk/gcloud.mk
include mk/terraform.mk

