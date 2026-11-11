# terraform-modules

Terraform modules for problems that keep coming back in production work:
proving that backups restore, protecting applications that cannot be patched,
giving access to servers without opening ports, and keeping cloud cost under
control.

Each module starts from a question someone had to answer under pressure. The
README of each module says what that question is, how the module answers it,
and which trade-offs were made on the way.

## Modules

| Module | Cloud | What it answers |
|--------|-------|-----------------|
| [aws-backup-restore-drill](modules/aws-backup-restore-drill) | AWS | Does the database backup actually restore, is the data in it recent, and how long does the restore take? |

Planned next: protection for a legacy application behind Cloudflare, private
access to a VM through Cloudflare Tunnel, and cost guardrails for Azure.

## What every module has

- **Tests.** Plan tests run with `terraform test` against a mocked provider, so
  they need no cloud account and run on every pull request.
- **A runnable example** under `examples/`.
- **A README that explains decisions**, not only inputs and outputs.
- **A status line** that says how far the module has been verified.

CI runs `terraform fmt`, `validate` and `test`, TFLint, Checkov, and the unit
tests of any code a module ships. Checks that are skipped are listed with a
reason in [.checkov.yaml](.checkov.yaml).

## Using a module

Reference a module by its path in this repository and pin it to a commit or a
tag:

```hcl
module "restore_drill" {
  source = "git::https://github.com/krusicb90/terraform-modules.git//modules/aws-backup-restore-drill?ref=<commit or tag>"

  # ...
}
```

## License

[MIT](LICENSE)
