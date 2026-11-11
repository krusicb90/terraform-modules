# Example: weekly restore drill for a PostgreSQL instance

Restores the latest snapshot of one RDS instance every Sunday at 03:00, runs
two SQL checks against the restored copy and notifies an SNS topic if the drill
fails.

The example expects the surrounding infrastructure to exist: the RDS instance
(backed up by AWS Backup), a VPC with private subnets, a DB subnet group for
the restored copy, a Secrets Manager secret with the database credentials, and
a Lambda layer with the `pg8000` driver.

```sh
../../scripts/build-driver-layer.sh postgres
terraform init
terraform plan -var-file=example.tfvars
```
