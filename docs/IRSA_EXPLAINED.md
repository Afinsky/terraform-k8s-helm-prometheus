# IRSA: как ServiceAccount в Kubernetes получает права в AWS IAM

Kubernetes ничего не знает про IAM. AWS ничего не знает про Kubernetes
ServiceAccount. Прямого "маппинга" ServiceAccount ↔ IAM Role как отдельной
сущности не существует ни в K8s, ни в AWS. Это две однонаправленные ссылки,
которые физически связываются только в момент STS-запроса — через проверку
claim'а в JWT-токене.

Механизм называется **IRSA (IAM Roles for Service Accounts)**, построен
поверх стандартного **OIDC federation** в AWS IAM (та же техника работает
не только с EKS, но и с GitHub Actions, GitLab CI и любым OIDC-провайдером).

Пример ниже — по реальной конфигурации из этого репозитория
(`eks.tf`, `lbc.tf`, роль `aws-load-balancer-controller`).

---

## Шаг за шагом

### 1. У кластера уже есть свой OIDC-issuer

Это не AWS-фича, а нативная возможность самого Kubernetes
(`ServiceAccountIssuerDiscovery` + projected token volumes) — kube-apiserver
умеет подписывать JWT для подов и публиковать JWKS (публичные ключи) по
HTTPS. EKS выставляет этот issuer наружу как публичный URL вида
`https://oidc.eks.<region>.amazonaws.com/id/<cluster-id>`.

### 2. AWS должен довериться этому issuer'у — регистрация IdP

`module.eks` (terraform-aws-modules/eks/aws) под капотом создаёт
`aws_iam_openid_connect_provider`, указывающий на issuer из шага 1. Это и
есть `module.eks.oidc_provider_arn` / `module.eks.oidc_provider`,
переиспользуемые в `vpc_cni`, `ebs_csi_driver` и `lb_controller`
(`eks.tf`, `lbc.tf`). Это разовая настройка на уровне кластера — от неё
зависят все IAM-роли для подов.

### 3. IAM Role с trust policy, доверяющей конкретному SA — чисто AWS-сторона

Из `lbc.tf` (роль `lb_controller`):

```json
"Principal": { "Federated": "${module.eks.oidc_provider_arn}" },
"Action": "sts:AssumeRoleWithWebIdentity",
"Condition": {
  "StringEquals": {
    "${module.eks.oidc_provider}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller",
    "${module.eks.oidc_provider}:aud": "sts.amazonaws.com"
  }
}
```

Роль говорит: "разрешаю AssumeRole кому угодно, кто предъявит JWT,
подписанный *этим конкретным* OIDC-провайдером, у которого в claim `sub`
буквально строка `system:serviceaccount:kube-system:aws-load-balancer-controller`".
Это условие целиком живёт в AWS — Kubernetes про существование этой роли
ничего не знает.

### 4. Kubernetes ServiceAccount с аннотацией — чисто K8s-сторона

Helm-чарт (`lbc.tf`) создаёт ServiceAccount с аннотацией:

```
eks.amazonaws.com/role-arn: <arn роли из шага 3>
```

Важно: сама по себе аннотация ничего не разрешает — это просто
метаданные-подсказка. Она не создаёт "право", она лишь говорит
вспомогательному механизму (шаг 5), какую роль подставить поду.

### 5. Связывающее звено — Pod Identity Webhook (есть в каждом EKS-кластере "из коробки")

При создании Pod'а с этим ServiceAccount admission webhook перехватывает
создание, смотрит на аннотацию SA и мутирует манифест пода, добавляя:

- env `AWS_ROLE_ARN=<arn роли>`
- env `AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token`
- projected volume с JWT-токеном для этого конкретного SA — токен
  запрашивается у kubelet через Kubernetes TokenRequest API, у него
  `aud=sts.amazonaws.com`, TTL ~1ч, kubelet сам его ротирует.

Это тоже происходит целиком на K8s-стороне — webhook не ходит в AWS, он
просто читает аннотацию и монтирует файл.

### 6. Рантайм: AWS SDK внутри пода сам обменивает JWT на настоящие AWS-креды

Любой современный AWS SDK при старте видит `AWS_WEB_IDENTITY_TOKEN_FILE` и
автоматически (без кода приложения) читает файл и вызывает:

```
sts:AssumeRoleWithWebIdentity(RoleArn=$AWS_ROLE_ARN, WebIdentityToken=<содержимое файла>)
```

### 7. STS — единственное место, где маппинг реально проверяется

STS:

1. Проверяет подпись JWT по публичным ключам зарегистрированного в шаге 2
   OIDC IdP.
2. Сверяет claims `aud` и `sub` из токена с condition'ами в trust policy
   роли (шаг 3).
3. Если совпало — выдаёт временные `AccessKeyId/SecretAccessKey/SessionToken`
   (~1ч), уже ограниченные правами `aws_iam_policy.lb_controller`.

Никаких долгоживущих ключей в кластере нет; каждый вызов в CloudTrail
атрибутируется конкретной паре роль/ServiceAccount.

---

## Итог — где именно "мапится"

| Что | Где живёт | Что делает |
|---|---|---|
| Аннотация на SA (`eks.amazonaws.com/role-arn`) | K8s | подсказка для webhook, какую роль подставить в env |
| Trust policy роли (`sub` = `system:serviceaccount:<ns>:<sa>`) | AWS IAM | **фактическая, криптографически проверяемая** привязка |
| JWT токен пода | выпускается K8s, валидируется AWS | мост — единственный артефакт, пересекающий границу систем |

Реальная граница доверия — это trust policy роли + подпись OIDC-провайдера,
а не аннотация на SA. Аннотацию можно вообще не ставить (задать
`AWS_ROLE_ARN` вручную в манифесте пода) — STS всё равно выдаст креды, если
`sub` в JWT совпадёт с condition в trust policy. Отсюда практическое
следствие: `aws_iam_role_policy_attachment.lb_controller` можно
провязать на *любой* SA в любом namespace — единственное, что реально
ограничивает "кто может представиться этой ролью", это точная строка
`namespace:serviceaccount-name` в condition.

## Побочный вывод для security-review

Любой, кто может создать/пропатчить ServiceAccount
`kube-system/aws-load-balancer-controller` или запустить под с этим SA
(т.е. имеет RBAC-права на это в кластере), фактически может ассьюмить роль
`lb_controller` с её IAM-правами — RBAC на этот конкретный SA в кластере
становится продолжением IAM-периметра.

## Аналогичные примеры в этом репозитории

Тот же паттерн используется для `vpc_cni` и `ebs_csi_driver` в `eks.tf`:
каждая роль доверяет строго одному `sub` (`system:serviceaccount:kube-system:aws-node`
и `system:serviceaccount:kube-system:ebs-csi-controller-sa` соответственно).

**Альтернатива, не используемая здесь**: EKS Pod Identity — новый механизм
AWS, который пропускает OIDC federation целиком, используя
`aws_eks_pod_identity_association` и in-cluster агента, говорящего с EKS
Auth API напрямую вместо STS. В этом репозитории не применяется — чтобы
оставаться консистентным с IRSA-паттерном, уже используемым для
`vpc_cni`/`ebs_csi_driver`.
