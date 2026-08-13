# Load balancer / ingress-nginx migration to AWS Load Balancer Controller

## Who was creating the load balancer before

Nobody you'd installed — the **legacy in-tree AWS cloud provider** (bundled into the EKS control plane) was reconciling it. Your `ingress-nginx` Service had `service.beta.kubernetes.io/aws-load-balancer-type: nlb`, a value only that legacy path understands. It's the same integration your last commit ("fix: run controller - legacy way") worked around — there was no AWS Load Balancer Controller pod running at all.

That path has two real costs: it only supports **instance targets** (client → NLB → NodePort → kube-proxy → pod, an extra hop that also obscures the real client IP unless you bolt on PROXY protocol), and its annotation set has been frozen for years since AWS's development effort moved to the out-of-cluster controller.

## What was changed

**`lbc.tf` (new)** — installs the **AWS Load Balancer Controller** properly: an IRSA role scoped to `system:serviceaccount:kube-system:aws-load-balancer-controller` (same pattern the `vpc_cni`/`ebs_csi_driver` roles in `eks.tf` already use), the official upstream IAM policy (`iam-policy-aws-load-balancer-controller.json`, downloaded fresh from the controller's repo, not hand-typed), and the `helm_release` for the controller itself.

**`nginx.yaml`** — switched the Service annotations from the legacy `aws-load-balancer-type: nlb` to `external` + `aws-load-balancer-nlb-target-type: ip`. That hands the Service to the new controller and makes the NLB target **pod IPs directly** — no NodePort hop, and the real client IP is preserved natively (so the `proxy-protocol` annotation was also dropped, which nginx was never actually configured to parse — that was a latent bug: TLS-at-NLB + unparsed PROXY protocol headers would have broken every connection the moment traffic flowed through it).

Also added `controller.config.ssl-redirect: "false"`. This setup terminates TLS at the NLB (ACM cert via `aws-load-balancer-ssl-cert`) and forwards **plaintext** to nginx (`targetPorts.https: http`). Without disabling nginx's own redirect, nginx can't tell an HTTPS request from an HTTP one and would 308-redirect HTTPS traffic back to HTTPS — an infinite loop. This was a live bug, not a stylistic change.

**`app.yaml`** — removed the `alb.ingress.kubernetes.io/*` annotations on the `photoapp` Ingress. Since `ingressClassName: nginx` is set, no ALB controller was ever going to see them (no ALB controller is run) — dead config, likely copy-pasted from an ALB-Ingress tutorial.

**`nginx.tf`** — added `depends_on = [helm_release.aws_load_balancer_controller]` so the Service isn't created before the controller exists to reconcile it.

**`README.md`** — regenerated via `terraform-docs` to reflect the new resources (matches what the pre-commit hook would produce).

Ran `terraform fmt`, `terraform validate`, and the project's `tflint` rule set — all clean. `terraform plan`/`apply` was not run and state was not touched.

## One thing worth knowing about, not changed

AWS's newer answer to all of this is **EKS Auto Mode** — the control plane runs load-balancer (and node/storage) provisioning itself, no controller or IRSA role to manage at all. It's the direction AWS is pushing new clusters toward, and the standalone AWS Load Balancer Controller is now in bug-fix-only mode upstream. This wasn't switched to because it also changes how node groups are managed (Karpenter-style NodeClass/NodePool instead of the current `eks_managed_node_groups`), which is a bigger structural change than "fix the load balancer." Worth scoping out separately if that direction is wanted.

**Verified since the first draft of this doc** (see `LOAD_BALANCER_DEEP_DIVE.md`, Q10/В10 for the full detail): the chart version was checked live via `helm search repo eks/aws-load-balancer-controller --versions` and bumped from the originally-guessed `1.13.0` to the current `3.5.0` (a versioning-scheme realignment, not a risky jump — checked the v3.0.0 release notes first, no breaking changes apply here); the `iam-policy-aws-load-balancer-controller.json` in this repo was re-diffed against the live upstream source and is still byte-identical, so it didn't need re-pulling; and the security-group concern below the ACM cert is resolved, not open — AWS LBC auto-manages backend security-group rules by default when no custom frontend SG is set (which is the case here), so `cluster_security_group_additional_rules = {}` in `eks.tf` is fine as-is. The only item still requiring a live cluster is checking NLB target-group health after the first `terraform apply`.

---

# Миграция load balancer / ingress-nginx на AWS Load Balancer Controller

## Кто создавал load balancer раньше

Никакой отдельно установленный контроллер — этим занимался **legacy in-tree AWS cloud provider** (встроенный в control plane EKS). У Service `ingress-nginx` была аннотация `service.beta.kubernetes.io/aws-load-balancer-type: nlb` — значение, которое понимает только этот legacy-путь. Это тот же механизм, вокруг которого был написан обходной путь в последнем коммите ("fix: run controller - legacy way") — AWS Load Balancer Controller как под в кластере вообще не был запущен.

У этого пути два реальных недостатка: он поддерживает только **instance targets** (клиент → NLB → NodePort → kube-proxy → под, лишний хоп, который к тому же скрывает реальный IP клиента, если не подключить PROXY protocol), а набор поддерживаемых аннотаций заморожен уже много лет, так как разработка AWS сместилась на контроллер, работающий вне кластера.

## Что было изменено

**`lbc.tf` (новый файл)** — устанавливает **AWS Load Balancer Controller** правильным образом: IRSA-роль, привязанная к `system:serviceaccount:kube-system:aws-load-balancer-controller` (тот же паттерн, что уже используется для ролей `vpc_cni`/`ebs_csi_driver` в `eks.tf`), официальная IAM-политика от разработчиков контроллера (`iam-policy-aws-load-balancer-controller.json`, скачана напрямую из репозитория контроллера, а не написана вручную), и сам `helm_release` для контроллера.

**`nginx.yaml`** — аннотации Service изменены с устаревшей `aws-load-balancer-type: nlb` на `external` + `aws-load-balancer-nlb-target-type: ip`. Это передаёт Service новому контроллеру и заставляет NLB направлять трафик **напрямую на IP подов** — без хопа через NodePort, при этом реальный IP клиента сохраняется нативно (поэтому аннотация `proxy-protocol` тоже была убрана — nginx на самом деле никогда не был настроен её парсить: это была скрытая ошибка, из-за которой при TLS-терминации на NLB и неразобранных заголовках PROXY protocol все соединения были бы сломаны).

Также добавлена `controller.config.ssl-redirect: "false"`. В текущей схеме TLS терминируется на NLB (сертификат ACM через `aws-load-balancer-ssl-cert`), а до nginx доходит **незашифрованный** трафик (`targetPorts.https: http`). Без отключения собственного редиректа nginx не может отличить HTTPS-запрос от HTTP и делал бы 308-редирект HTTPS-трафика обратно на HTTPS — бесконечный цикл. Это была реальная ошибка, а не стилистическая правка.

**`app.yaml`** — удалены аннотации `alb.ingress.kubernetes.io/*` у Ingress `photoapp`. Поскольку указан `ingressClassName: nginx`, ни один ALB-контроллер их никогда бы не увидел (ALB-контроллер вообще не используется) — мёртвая конфигурация, вероятно, скопированная из туториала по ALB-Ingress.

**`nginx.tf`** — добавлена `depends_on = [helm_release.aws_load_balancer_controller]`, чтобы Service не создавался раньше, чем появится контроллер, способный его обработать.

**`README.md`** — пересобран через `terraform-docs`, чтобы отразить новые ресурсы (соответствует тому, что сгенерировал бы pre-commit hook).

Выполнены `terraform fmt`, `terraform validate` и набор правил `tflint` проекта — всё чисто. `terraform plan`/`apply` не запускались, состояние (state) не затрагивалось.

## Что стоит знать, но не было изменено

Более новый ответ AWS на всё это — **EKS Auto Mode**: control plane сам занимается провижининогом load balancer'ов (а также нод и storage), без необходимости управлять отдельным контроллером или IRSA-ролью. Это направление, в которое AWS подталкивает новые кластеры, а самостоятельный AWS Load Balancer Controller теперь получает только исправления багов. Переход на Auto Mode не был сделан, так как это также меняет способ управления node group (NodeClass/NodePool в стиле Karpenter вместо текущих `eks_managed_node_groups`) — это более крупное структурное изменение, чем "починить load balancer". Имеет смысл вынести это в отдельную задачу, если такое направление интересно.

**Проверено после первого черновика этого документа** (подробности — в `LOAD_BALANCER_DEEP_DIVE.md`, В10/Q10): версия чарта была проверена вживую через `helm search repo eks/aws-load-balancer-controller --versions` и поднята с изначально предположенной `1.13.0` до актуальной `3.5.0` (это смена схемы версионирования, а не рискованный скачок — предварительно проверены release notes v3.0.0, breaking changes здесь не применимы); `iam-policy-aws-load-balancer-controller.json` в репозитории сверен построчно с актуальным апстримом и оказался побайтово идентичен, перекачивать заново не потребовалось; а вопрос про security group ниже сертификата ACM закрыт, а не открыт — AWS LBC по умолчанию сам управляет правилами backend security group, когда своя frontend SG не задана (это и есть текущий случай), так что `cluster_security_group_additional_rules = {}` в `eks.tf` — это нормально как есть. Единственный пункт, для которого всё ещё нужен живой кластер, — проверка здоровья target group NLB после первого `terraform apply`.
