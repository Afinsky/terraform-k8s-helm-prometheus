# DNS management — tasks for the next session

Not implemented yet. Captures the discussion from the load-balancer/ingress
work in `LOAD_BALANCER_MIGRATION.md` / `LOAD_BALANCER_DEEP_DIVE.md`: once the
AWS Load Balancer Controller + ingress-nginx setup is live, host-based
`Ingress` rules (e.g. `host: myapp.abotyan.click` in `app.yaml`) still need a
matching DNS record pointing at the NLB — nothing in the repo creates that
today. `route53.tf` only *reads* the existing zone
(`data "aws_route53_zone" "zone"`); it writes nothing.

## Decision needed first

Pick one of the three approaches below before writing any code. Open
question to answer at the start of next session: how many apps/hosts is this
expected to serve — still just `photoapp` on one host, or more services
incoming? That answer decides which option makes sense.

## Option A — Manual `aws_route53_record` in Terraform

Best if it stays 1-2 static hosts.

- [ ] Add a `data "kubernetes_service" "ingress_nginx_controller"` (or read
      `helm_release.ingress_nginx` outputs some other way) to get
      `.status.load_balancer.ingress[0].hostname` for the NLB.
- [ ] Add an `aws_route53_record` of type **CNAME** (not ALIAS — ALIAS needs
      the load balancer's own hosted-zone ID, which means a
      `data "aws_lb"` lookup by tag; the NLB is created out-of-band by
      Helm/AWS LBC, not directly by Terraform, so that lookup can fail on a
      first-ever `apply` before the LB exists — a real chicken-and-egg
      problem worth designing around, not hitting by surprise).
- [ ] One record per host declared in any `Ingress` — must be kept in sync
      by hand.

## Option B — Wildcard record

Best fit given `acm.tf` already requests a wildcard SAN
(`*.${local.zone_name}`) on the ACM cert — this option uses that wildcard
cert as designed, instead of leaving it unused.

- [ ] Single `aws_route53_record` for `*.abotyan.click` → NLB hostname
      (CNAME, same chicken-and-egg note as Option A).
- [ ] All routing then happens inside nginx via Host header; new `Ingress`
      hosts under the same root domain need zero DNS changes.
- [ ] Note the tradeoff: no per-host DNS record means DNS stops being a
      source of truth for "what hosts actually exist," and this only covers
      subdomains of `abotyan.click` — a future custom root domain would still
      need its own record.

## Option C — external-dns (the actual production pattern)

Best if more services/teams get added later; this is what's used almost
universally alongside ingress-nginx + AWS LBC in real deployments.

- [ ] New `dns.tf` (or extend `lbc.tf`): IRSA role for
      `system:serviceaccount:external-dns:external-dns` (same pattern as
      `aws_iam_role.lb_controller` in `lbc.tf`), policy scoped to
      `route53:ChangeResourceRecordSets`, `route53:ListHostedZones`,
      `route53:ListResourceRecordSets`, `route53:ListTagsForResource`.
- [ ] `helm_release.external_dns` (chart `external-dns/external-dns`,
      `kube-system` or its own namespace), configured with:
  - `--source=ingress`
  - `--publish-service=ingress-nginx/ingress-nginx-controller` (needed
    because the DNS-worthy hostname lives on the ingress-nginx Service's
    status, not directly on a raw ALB-backed Ingress — this repo uses
    `ingressClassName: nginx`, not AWS LBC's Ingress path)
  - `--domain-filter=abotyan.click` (scope to the one zone, avoid touching
    others in the account)
  - `--policy=upsert-only` (create/update only, never auto-delete — safer
    for a zone that isn't dedicated solely to this cluster; revisit if the
    zone becomes cluster-owned)
  - TXT registry (default) for record ownership tracking — confirm
    `--txt-owner-id` is set to something stable (e.g. cluster name) so
    re-applies don't fight over ownership.
- [ ] `depends_on = [module.eks, helm_release.aws_load_balancer_controller]`
      (same access-entry / controller-readiness reasoning as
      `helm_release.ingress_nginx` in `nginx.tf`).
- [ ] Decide RBAC scope: cluster-wide watch, or namespace-restricted if this
      cluster ever becomes multi-tenant.

## Recommendation if no strong preference next session

Given this is currently a single app (`photoapp`) on a personal domain:
start with **Option B (wildcard)** — it's a one-record change, uses the
already-provisioned wildcard cert, and doesn't add a new controller/IRSA
role to operate. Revisit **Option C (external-dns)** if/when more than one
distinct hostname pattern or more than a couple of services show up — same
"why we didn't jump to it immediately" reasoning as EKS Auto Mode in
`LOAD_BALANCER_DEEP_DIVE.md` Q9.

---
---

# Управление DNS-записями — задачи для следующей сессии

Пока не реализовано. Фиксирует обсуждение из работы над load balancer/ingress
(`LOAD_BALANCER_MIGRATION.md` / `LOAD_BALANCER_DEEP_DIVE.md`): как только
связка AWS Load Balancer Controller + ingress-nginx заработает, правилам
`Ingress` по хосту (например, `host: myapp.abotyan.click` в `app.yaml`)
по-прежнему будет нужна соответствующая DNS-запись, указывающая на NLB — в
репозитории сейчас этого нет вообще. `route53.tf` только *читает*
существующую зону (`data "aws_route53_zone" "zone"`), ничего в неё не пишет.

## Сначала нужно решение

Перед тем как писать код, выбрать один из трёх вариантов ниже. Вопрос,
который стоит решить в начале следующей сессии: сколько приложений/хостов
это должно обслуживать — по-прежнему только `photoapp` на одном хосте, или
планируются другие сервисы? Ответ определяет, какой вариант имеет смысл.

## Вариант A — Ручная `aws_route53_record` в Terraform

Подходит, если хостов останется 1-2 и они статичны.

- [ ] Добавить `data "kubernetes_service" "ingress_nginx_controller"` (или
      иначе получить статус) для чтения
      `.status.load_balancer.ingress[0].hostname` NLB.
- [ ] Добавить `aws_route53_record` типа **CNAME** (не ALIAS — ALIAS требует
      hosted-zone ID самого балансировщика, а значит lookup через
      `data "aws_lb"` по тегу; NLB создаётся не напрямую Terraform, а
      Helm/AWS LBC, поэтому такой lookup может не сработать на самом первом
      `apply`, пока балансировщика ещё не существует — реальная проблема
      "курицы и яйца", которую стоит заранее учесть в дизайне, а не
      наткнуться на неё внезапно).
- [ ] По одной записи на каждый хост, объявленный в любом `Ingress` —
      синхронизировать вручную.

## Вариант B — Wildcard-запись

Хорошо ложится на то, что `acm.tf` уже заказывает wildcard SAN
(`*.${local.zone_name}`) для ACM-сертификата — этот вариант использует
wildcard-сертификат по назначению, а не оставляет его невостребованным.

- [ ] Одна `aws_route53_record` для `*.abotyan.click` → hostname NLB (CNAME,
      та же оговорка про "курицу и яйцо", что и в варианте A).
- [ ] Дальше вся маршрутизация происходит внутри nginx по Host-заголовку;
      новым хостам `Ingress` под тем же корневым доменом изменения DNS не
      нужны вообще.
- [ ] Учесть компромисс: без записи на каждый хост DNS перестаёт быть
      источником правды о том, какие хосты реально существуют, и вариант
      покрывает только поддомены `abotyan.click` — для будущего отдельного
      корневого домена всё равно понадобится своя запись.

## Вариант C — external-dns (реальный прод-паттерн)

Подходит, если позже добавятся другие сервисы/команды; именно это почти
повсеместно используется вместе с ingress-nginx + AWS LBC в реальных
проектах.

- [ ] Новый `dns.tf` (или расширить `lbc.tf`): IRSA-роль для
      `system:serviceaccount:external-dns:external-dns` (тот же паттерн, что
      `aws_iam_role.lb_controller` в `lbc.tf`), политика с правами
      `route53:ChangeResourceRecordSets`, `route53:ListHostedZones`,
      `route53:ListResourceRecordSets`, `route53:ListTagsForResource`.
- [ ] `helm_release.external_dns` (чарт `external-dns/external-dns`, неймспейс
      `kube-system` или отдельный), с настройками:
  - `--source=ingress`
  - `--publish-service=ingress-nginx/ingress-nginx-controller` (нужно, так
    как DNS-имя, достойное записи, лежит в статусе Service самого
    ingress-nginx, а не напрямую в Ingress с ALB — в этом репозитории
    используется `ingressClassName: nginx`, а не путь AWS LBC через Ingress)
  - `--domain-filter=abotyan.click` (ограничить одной зоной, не трогать
    остальные в аккаунте)
  - `--policy=upsert-only` (только создание/обновление, без автоудаления —
    безопаснее для зоны, которая не выделена исключительно под этот
    кластер; пересмотреть, если зона станет "собственностью" кластера)
  - TXT registry (по умолчанию) для отслеживания владения записями —
    убедиться, что `--txt-owner-id` задан чем-то стабильным (например,
    именем кластера), чтобы повторные `apply` не конфликтовали за
    владение.
- [ ] `depends_on = [module.eks, helm_release.aws_load_balancer_controller]`
      (та же логика про готовность access entry/контроллера, что и у
      `helm_release.ingress_nginx` в `nginx.tf`).
- [ ] Решить масштаб RBAC: наблюдение по всему кластеру или ограничение по
      неймспейсам, если кластер когда-нибудь станет мультитенантным.

## Рекомендация, если в следующей сессии не будет чёткого предпочтения

Учитывая, что сейчас это одно приложение (`photoapp`) на личном домене:
начать с **варианта B (wildcard)** — это изменение в одну запись,
использует уже заказанный wildcard-сертификат и не добавляет новый
контроллер/IRSA-роль в эксплуатацию. Вернуться к **варианту C
(external-dns)**, если/когда появится больше одного паттерна хостов или
больше пары сервисов — та же логика "почему не прыгнули сразу", что и с EKS
Auto Mode в `LOAD_BALANCER_DEEP_DIVE.md`, В9.
