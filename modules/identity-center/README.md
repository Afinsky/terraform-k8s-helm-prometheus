# 01-identity

Terraform module for Phase 1 + Phase 2 of the PLAT-101 lab, applied via
[`accounts/abotyan001/us-east-1/01-identity-center`](../../accounts/abotyan001/us-east-1/01-identity-center)'s
`terragrunt.hcl`. Creates the AWS Organization, groups, users, group
memberships, and all permission sets/assignments. Structure and backend
pattern match [`eks-cluster`](../eks-cluster): S3 backend and inputs managed by
Terragrunt (see `../../root.hcl` and that layer's `terragrunt.hcl`).

Terraform can't handle only the things the `hashicorp/aws` provider has no
resource for:
- enabling IAM Identity Center as an organization instance;
- customizing the access portal URL;
- setting a password/one-time password for created users;
- activating CloudFormation's Organizations access (see step 3 below) —
  needed once, account-wide, before `aws_cloudformation_stack_set.terraform_target`
  (`account_access_stackset.tf`) can create a `SERVICE_MANAGED` StackSet.

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
# 3. One-time, account-wide: activate CloudFormation's Organizations access.
#    Enabling Organizations trusted access for
#    member.org.stacksets.cloudformation.amazonaws.com (organization.tf) is
#    not enough — CloudFormation has its own separate switch, with no
#    Terraform resource for it (checked provider >= 6.60.0's schema).
#    Without this, aws_cloudformation_stack_set.terraform_target fails with:
#    "ValidationError: You must enable organizations access to operate a
#    service managed stack set". Run once, from the management account:
aws cloudformation describe-organizations-access --profile lab-admin --region us-east-1
aws cloudformation activate-organizations-access --profile lab-admin --region us-east-1

# 4. Everything else: groups, users, memberships, PlatformAdmin, EKSDev-*,
#    and the terraform-target StackSet.
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

See `variables.tf`. `profile` is the same IAM profile used by `../eks-cluster`'s
`terragrunt.hcl` (e.g. `terraform`): at the time of the first apply, the
`lab-admin` SSO profile doesn't exist yet.
