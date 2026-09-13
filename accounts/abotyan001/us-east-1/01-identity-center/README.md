# 01-identity

Terraform stack for Phase 1 + Phase 2 of the PLAT-101 lab. Creates the AWS
Organization, groups, users, group memberships, and all permission
sets/assignments. Structure and backend pattern match
[`develop`](../develop): S3 backend and inputs managed by Terragrunt
(see `../../../../root.hcl` and this stack's `terragrunt.hcl`).

Terraform can't handle only the things the `hashicorp/aws` provider has no
resource for:
- enabling IAM Identity Center as an organization instance;
- customizing the access portal URL;
- setting a password/one-time password for created users.

## Order of operations

```bash
terragrunt init

# 1. Create only the Organization — Identity Center doesn't exist yet, the
#    ssoadmin_instances data source would otherwise fail.
terragrunt apply -target=aws_organizations_organization.this
```

Then by hand in the console (region `us-east-1`):
1. **IAM Identity Center → Enable → Enable with AWS Organizations**
2. **Settings → Access portal URL → Customize**, note the URL

```bash
# 2. Everything else: groups, users, memberships, PlatformAdmin, EKSDev-*
terragrunt apply
```

Then by hand: for `aliaksei`/`alice`/`bob` in Identity Center →
**Reset password → Generate one-time password**, save the passwords.

## Teardown

```bash
terragrunt destroy
```

Removes everything this stack created, including the Organization. If it
already has member accounts, Organizations won't let you delete it — remove
those first.

## Variables

See `variables.tf`. `profile` is the same IAM profile used by `../develop`'s
`terragrunt.hcl` (e.g. `terraform`): at the time of the first apply, the
`lab-admin` SSO profile doesn't exist yet.
