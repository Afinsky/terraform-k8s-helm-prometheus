# 01-identity

Terraform-стек Фазы 1 + Фазы 2 лабы PLAT-101. Создаёт AWS Organization, группы,
пользователей, membership и все permission sets/assignments. Структура и
backend-паттерн — как в [`environments/develop`](../../environments/develop):
S3-backend с partial config через `.conf`-файл, переменные через `.tfvars`.

Terraform не умеет только то, для чего у провайдера `hashicorp/aws` физически
нет ресурса:
- включить IAM Identity Center как organization instance;
- кастомизировать access portal URL;
- задать пароль/one-time password созданным пользователям.

## Порядок

```bash
terraform init -backend-config=identity.conf

# 1. Создаём только Organization — Identity Center ещё нет, data-источник
#    ssoadmin_instances иначе упадёт.
terraform apply -target=aws_organizations_organization.this -var-file=identity.tfvars
```

Дальше руками в консоли (регион `us-east-1`):
1. **IAM Identity Center → Enable → Enable with AWS Organizations**
2. **Settings → Access portal URL → Customize**, запиши URL

```bash
# 2. Всё остальное: группы, юзеры, membership, PlatformAdmin, EKSDev-*
terraform apply -var-file=identity.tfvars
```

Потом руками: для `aliaksei`/`alice`/`bob` в Identity Center →
**Reset password → Generate one-time password**, сохрани пароли.

## Уборка

```bash
terraform destroy -var-file=identity.tfvars
```

Удалит всё, что создал этот стек, включая Organization. Если внутри неё
уже есть member-аккаунты — Organizations не даст её удалить, сначала убери их.

## Переменные

См. `variables.tf`. `profile` — тот же IAM-профиль, что используется в
`environments/develop/develop.tfvars` (например `terraform`): на момент
первого apply SSO-профиля `lab-admin` ещё не существует.
