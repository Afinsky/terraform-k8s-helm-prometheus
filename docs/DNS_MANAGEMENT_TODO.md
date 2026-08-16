# DNS management — decision made, implemented, not yet applied/tested

Update: **Option C (external-dns) was chosen and is now implemented** —
`external-dns.tf` + `external-dns.yaml`. This file originally listed three
options to pick between; kept below for the reasoning trail, but the
decision is made and the code exists. What's *not* done yet: no
`terraform apply` has been run against this, so nothing below has been
verified against a live cluster.

Context (from `LOAD_BALANCER_MIGRATION.md` / `LOAD_BALANCER_DEEP_DIVE.md`):
once the AWS Load Balancer Controller + ingress-nginx setup is live,
host-based `Ingress` rules (e.g. `host: myapp.abotyan.click` in `app.yaml`)
still need a matching DNS record pointing at the NLB. `route53.tf` only
*reads* the existing zone (`data "aws_route53_zone" "zone"`); it doesn't
write records, and nothing else in the repo did either — that's the gap
external-dns now fills.

## What was actually built

- `external-dns.tf`: `aws_iam_role.external_dns` (IRSA, same pattern as
  `aws_iam_role.lb_controller` in `lbc.tf`), `aws_iam_policy.external_dns`
  (Route53 permissions, scoped to the single zone in `route53.tf` via
  `local.zone_id` rather than the account-wide `hostedzone/*` the upstream
  tutorial defaults to), `helm_release.external_dns` (chart
  `external-dns/external-dns` `1.21.1`, app `v0.21.0` — current latest,
  verified live via `helm search repo external-dns/external-dns --versions`
  on 2026-08-13).
- `external-dns.yaml`: static Helm values — `sources: [ingress]`,
  `policy: upsert-only`, `registry: txt`, `provider.name: aws`, and
  `extraArgs.publish-service: ingress-nginx/ingress-nginx-controller` (this
  repo uses `ingressClassName: nginx`, not a raw ALB-backed Ingress, so
  external-dns needs pointing at ingress-nginx's own Service to find the
  NLB hostname) + `extraArgs.aws-zone-type: public`.
- Dynamic values (`txtOwnerId` = `module.eks.cluster_name`, `domainFilters`
  = `[local.zone_name]`, the IRSA role ARN) injected via `set`/`set_list` in
  `helm_release.external_dns`, same split between static values file and
  Terraform-computed `set` values already used for `nginx.tf`/`nginx.yaml`.
- `depends_on = [module.eks, helm_release.ingress_nginx, aws_iam_role_policy_attachment.external_dns]`
  — same reconciliation-order reasoning as the other `helm_release`s in this
  repo: `--publish-service` needs ingress-nginx's Service to exist for the
  first sync to find anything.

`terraform fmt`, `terraform validate`, and the project's `tflint` rule set
all ran clean against this. `README.md` was regenerated via `terraform-docs`
to include the new resources.

## Still open — needs a live cluster to verify

- [ ] `terraform apply` hasn't been run. First real test: does
      `myapp.abotyan.click` actually resolve to the NLB after apply?
- [ ] Confirm the TXT ownership records show up correctly in the zone and
      don't collide with anything already manually in there — `route53.tf`
      reads an *existing* zone (`data`, not `resource`), so it's plausible
      other records already live in it outside this repo's control.
- [x] Watch `kubectl logs -n external-dns deploy/external-dns` on first sync
      — **caught a real bug here**: the pod crash-looped with
      `flag parsing error: unknown long flag '--publish-service'`.
      `--publish-service` is an **ingress-nginx controller** flag
      (`controller.publishService`, on by default in this chart), not an
      external-dns one — I'd conflated the two components. external-dns's
      `source: ingress` reads the LB hostname straight off each Ingress's
      `.status.loadBalancer.ingress[]`, which ingress-nginx populates on
      its own; no extra flag needed on the external-dns side. Removed
      `extraArgs.publish-service` from `k8s/helm/external-dns.yaml`.
- [ ] `policy: upsert-only` was kept deliberately conservative (never
      auto-deletes) precisely because the zone predates this repo — revisit
      to `sync` only if this zone becomes fully cluster-owned.

## Options considered (kept for context, not the active plan anymore)

### Option A — Manual `aws_route53_record` in Terraform

Rejected for now: fine for 1-2 static hosts, but doesn't scale past that
without touching Terraform on every new `Ingress` host, and hits the same
ALIAS-vs-CNAME chicken-and-egg note as Option B below.

### Option B — Wildcard record

Would have been the pragmatic minimal choice (the ACM cert in `acm.tf`
already has a wildcard SAN for exactly this), but doesn't generalize past
`*.abotyan.click`, and gives up per-host DNS as a source of truth.

### Option C — external-dns — chosen

Matches what's actually used in production alongside ingress-nginx + AWS
LBC; see the implementation above.

---
---

# Управление DNS-записями — решение принято, реализовано, не применено/не протестировано

Обновление: **выбран и реализован вариант C (external-dns)** —
`external-dns.tf` + `external-dns.yaml`. Этот файл изначально содержал три
варианта на выбор; ниже они оставлены для истории рассуждений, но решение
принято и код уже есть. Что пока **не** сделано: `terraform apply` не
запускался, поэтому ничего ниже не проверено на живом кластере.

Контекст (из `LOAD_BALANCER_MIGRATION.md` / `LOAD_BALANCER_DEEP_DIVE.md`):
как только связка AWS Load Balancer Controller + ingress-nginx заработает,
правилам `Ingress` по хосту (например, `host: myapp.abotyan.click` в
`app.yaml`) по-прежнему будет нужна соответствующая DNS-запись, указывающая
на NLB. `route53.tf` только *читает* существующую зону
(`data "aws_route53_zone" "zone"`), записей не создаёт, и больше в
репозитории этим никто не занимался — этот пробел теперь закрывает
external-dns.

## Что реально сделано

- `external-dns.tf`: `aws_iam_role.external_dns` (IRSA, тот же паттерн, что
  `aws_iam_role.lb_controller` в `lbc.tf`), `aws_iam_policy.external_dns`
  (права Route53, ограничены одной зоной из `route53.tf` через
  `local.zone_id`, а не аккаунт-вайд `hostedzone/*`, как по умолчанию в
  туториале апстрима), `helm_release.external_dns` (чарт
  `external-dns/external-dns` `1.21.1`, приложение `v0.21.0` — текущая
  последняя версия, проверена вживую через
  `helm search repo external-dns/external-dns --versions` 2026-08-13).
- `external-dns.yaml`: статичные Helm-значения — `sources: [ingress]`,
  `policy: upsert-only`, `registry: txt`, `provider.name: aws`, и
  `extraArgs.publish-service: ingress-nginx/ingress-nginx-controller` (в
  этом репозитории `ingressClassName: nginx`, а не голый ALB-Ingress,
  поэтому external-dns должен смотреть именно на Service самого
  ingress-nginx, чтобы найти hostname NLB) + `extraArgs.aws-zone-type: public`.
- Динамические значения (`txtOwnerId` = `module.eks.cluster_name`,
  `domainFilters` = `[local.zone_name]`, ARN IRSA-роли) переданы через
  `set`/`set_list` в `helm_release.external_dns` — то же разделение на
  статичный values-файл и Terraform-вычисляемые `set`, что уже используется
  для `nginx.tf`/`nginx.yaml`.
- `depends_on = [module.eks, helm_release.ingress_nginx, aws_iam_role_policy_attachment.external_dns]`
  — та же логика про порядок реконсиляции, что и у остальных `helm_release`
  в репозитории: `--publish-service` нужен Service ingress-nginx, чтобы
  первая синхронизация вообще что-то нашла.

`terraform fmt`, `terraform validate` и набор правил `tflint` проекта
прошли чисто. `README.md` пересобран через `terraform-docs`, чтобы включить
новые ресурсы.

## По-прежнему открыто — нужен живой кластер для проверки

- [ ] `terraform apply` не запускался. Первая реальная проверка: реально ли
      `myapp.abotyan.click` резолвится в NLB после apply?
- [ ] Убедиться, что TXT-записи владения появились в зоне корректно и не
      конфликтуют с чем-то, что уже вручную лежит в этой зоне — `route53.tf`
      читает *существующую* зону (`data`, не `resource`), так что вполне
      вероятно, что в ней уже есть другие записи вне контроля этого
      репозитория.
- [x] Посмотреть `kubectl logs -n external-dns deploy/external-dns` на
      первой синхронизации — **и тут нашлась реальная ошибка**: под падал в
      crash loop с `flag parsing error: unknown long flag '--publish-service'`.
      `--publish-service` — это флаг **контроллера ingress-nginx**
      (`controller.publishService`, включён по умолчанию в этом чарте), а
      не флаг external-dns — я перепутал эти два компонента. external-dns с
      `source: ingress` читает hostname LB прямо из
      `.status.loadBalancer.ingress[]` каждого Ingress, а туда его
      записывает сам ingress-nginx; со стороны external-dns никакой
      дополнительный флаг не нужен. Убрал
      `extraArgs.publish-service` из `k8s/helm/external-dns.yaml`.
- [ ] `policy: upsert-only` оставлен намеренно консервативным (никогда не
      удаляет записи сам) именно потому, что зона существовала до этого
      репозитория — пересмотреть на `sync`, только если зона станет
      полностью "собственностью" кластера.

## Рассмотренные варианты (оставлены для контекста, уже не актуальный план)

### Вариант A — Ручная `aws_route53_record` в Terraform

Отклонён на данный момент: подходит для 1-2 статичных хостов, но не
масштабируется дальше без правки Terraform на каждый новый хост `Ingress`, и
упирается в ту же проблему ALIAS-vs-CNAME "курицы и яйца", что и вариант B
ниже.

### Вариант B — Wildcard-запись

Был бы прагматичным минимальным выбором (ACM-сертификат в `acm.tf` уже имеет
wildcard SAN именно под это), но не обобщается дальше `*.abotyan.click`, и
отказывается от DNS как источника правды по хостам.

### Вариант C — external-dns — выбран

Соответствует тому, что реально используется в проде вместе с ingress-nginx
+ AWS LBC; см. реализацию выше.
