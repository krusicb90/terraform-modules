# Example: guardrails for a development subscription

Sets a monthly budget with a forecast warning, a budget for one team's
resource group, a cost anomaly alert, required ownership tags, a VM size limit
for a sandbox and an evening shutdown for a build agent.

```sh
az login
terraform init
terraform apply -var-file=example.tfvars
```

The policies start in reporting mode. Check the compliance view in the Azure
portal, fix what it shows, then set `enforce_policies = true`.
