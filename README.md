# Development-Infrastructure for Serlo

## Introduction
Serlo's infrastructure is based on Terraform, Kubernetes and the Google Cloud Platform.

Currently we support three different environments:

1. **https://serlo-development.dev** (development environment for new infrastructure code, deployable by all serlo devs - https://github.com/serlo/infrastructure-env-dev)
2. **https://serlo-staging.dev** (staging environment to test and integrate infrastructure and apps, deployable only by infrastructure unit - https://github.com/serlo/infrastructure-env-staging)
3. **https://serlo.org** (production environment, deployable only by infrastructure unit - https://github.com/serlo/infrastructure-env-production)

To get access to our dev/staging environments please contact us.

## QuickStart
### Tools and preconditions 
- [Install terraform](https://learn.hashicorp.com/terraform/getting-started/install.html)
- [Install gcloud](https://cloud.google.com/sdk/install)
- [install gsutil](https://cloud.google.com/storage/docs/gsutil_install)
- [Install git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
- Get (read) access to project serlo-dev. Please contact one of the Devs.

```bash
# 1 Authenticate with your own account
gcloud auth login

# 2 Set project to "serlo-dev"
gcloud config set project serlo-dev

# 3 Clone this repo
git clone https://github.com/serlo/infrastructure-env-dev

# 4 Change to cloned dev environment folder
cd infrastructure-env-dev

# 5 Initialize your local setup
make terraform_init

# 6 Plan your changes
make terraform_plan

# 7 Deploy your changes to the gcloud dev environment
make terraform_apply
```

## How to connect to Google Cloud SQL instances
- [Download CloudSQL-Proxy](https://cloud.google.com/sql/docs/mysql/connect-external-app#proxy)
- Download secrets-folder (please follow [QuickStart](#quickstart))
- Find "instance connection name" via Google Cloud SQL Dashboard
- Start proxy:

```bash
./cloud_sql_proxy -instances=<INSTANCE_CONNECTION_NAME>=tcp:3306 -credential_file=<PATH_TO_CLOUDSQL_CREDENTIAL_FILE_IN_SECRETES_FOLDER> &
```
- Connect your Sql-Client to localhost:3306

## Setup a new environment (example: dev)
- Create new project 'serlo-dev' in Google Cloud
- Activate the following APIs:
    - storage-api.googleapis.com
    - container.googleapis.com (Kubernetes)
    - sqladmin.googleapis.com
    - iam.googleapis.com
- Create new service account for Terraform with role "Editor"
- Create new service account for SQL with role "Cloud SQL Client"
- Create bucket for terraform state
```bash
gsutil mb -p serlo-dev gs://serlo_dev_terraform
```
- Set versioning for bucket
```bash
gsutil versioning set on gs://serlo_dev_terraform
```
- Copy secrets_template to folder "secrets" and insert your own stuff
- Copy secrets to google bucket:
```bash
gsutil cp -r secrets gs://serlo_dev_terraform
- Modify the Makefile variables like env_name, gcloud_env_name ...
- Create your .tf files and start with terraform

## Important things after initial cluster setup
Because there is no easy way to GRANT/REVOKE privileges for the added SQL users, we have to run a few sql-scripts once after the cluster setup.

- Follow [How to connect to Google Cloud SQL instances](#how-to-connect-to-google-cloud-sql-instances)
- Connect to the MYSQL instance
- Run all sql-scripts of folder 'sql' with user 'serlo' and your favourite MYSQL-Client
