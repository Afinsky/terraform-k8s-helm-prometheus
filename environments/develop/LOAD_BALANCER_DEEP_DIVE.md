# AWS Load Balancer Controller + ingress-nginx — deep dive (Q&A)

Companion to `LOAD_BALANCER_MIGRATION.md`. That file says *what* changed; this
one goes under the hood — mechanics, packet paths, and the actual failure
modes each change fixes.

---

## Q1. What was actually creating the load balancer before, mechanically?

EKS's control plane runs a **service controller** as part of
`kube-controller-manager` (AWS operates this for you; you never see a pod for
it). It has a single job: watch every `Service` object cluster-wide, and for
any with `spec.type: LoadBalancer`, call the EC2/ELB API to create/update an
AWS load balancer for it.

This is the **in-tree / legacy AWS cloud provider** integration. It predates
the AWS Load Balancer Controller (LBC) by years and is what Kubernetes'
upstream deprecation effort (KEP-2395, "remove in-tree cloud providers") has
been trying to retire cluster-by-cluster across every cloud since ~2019. AWS
still ships it inside the EKS control plane for backward compatibility, but
has been steering users toward LBC since 2020.

It reads a small, frozen set of `service.beta.kubernetes.io/aws-load-balancer-*`
annotations — the same annotation *prefix* the modern LBC also listens on,
which is exactly why the misconfiguration was invisible: both controllers
speak the same annotation dialect, so `aws-load-balancer-type: nlb` looked
like a normal, working annotation. It's only the specific *value* (`nlb` vs
`external`) that decides which of the two controllers claims the Service.

**What it does *not* do:** manage security groups, support IP targets,
support NLB-level SGs, support target group attribute tuning, or gain any new
features. It has been functionally frozen for a long time.

---

## Q2. What's the actual packet path, before vs after?

**Before (legacy controller, instance targets):**

```
client
  │ TCP/TLS
  ▼
NLB (target = every EC2 node's instance ID, port = Service's NodePort)
  │ picks any registered node — not necessarily one running your pod
  ▼
node's kube-proxy (iptables/IPVS DNAT rules)
  │ may hop over the pod network to a *different* node
  ▼
pod

Source IP seen by the pod: the node's internal IP (SNAT'd by kube-proxy),
not the real client — unless PROXY protocol is used end-to-end.
```

**After (AWS Load Balancer Controller, IP targets):**

```
client
  │ TCP/TLS
  ▼
NLB (targets = pod IPs directly, discovered from EndpointSlices)
  │ VPC-routes straight to the pod's ENI IP — no node/kube-proxy involved
  ▼
pod

Source IP seen by the pod: the real client IP, preserved natively.
```

This is the practical meaning of "IP target mode removes a hop": it's not
just fewer network segments, it changes *who* is the target of the load
balancer — individual pods instead of nodes — which is only possible because
EKS's VPC CNI gives every pod a real, VPC-routable IP address (this wouldn't
work with an overlay CNI that hides pod IPs behind NAT).

---

## Q3. How does the AWS Load Balancer Controller actually work internally?

It's an ordinary Kubernetes controller (controller-runtime based) running as
a `Deployment` in `kube-system`. No magic beyond standard Kubernetes
mechanics:

1. **Watch loop**: list-watches `Service`, `Ingress`, `IngressClass`, and its
   own `TargetGroupBinding` CRD via the API server — the same
   watch-and-reconcile pattern any controller uses, not a per-request
   webhook call.
2. **Admission webhooks**: it registers a `MutatingWebhookConfiguration` and
   `ValidatingWebhookConfiguration`. The mutating webhook's main job is
   injecting a **pod readiness gate** into pods that will be targeted
   directly (IP mode) — this makes Kubernetes hold a pod at `NotReady` until
   the controller confirms the pod is actually registered *and* healthy in
   the AWS target group, closing a race where traffic could be sent to a pod
   before AWS even knows it exists, or where a pod gets pulled from Service
   endpoints before it's deregistered from the target group.
3. **Reconcile, for a Service annotated `aws-load-balancer-type: external`**:
   resolve desired state from annotations (scheme, target type, TLS cert,
   health check, cross-zone, etc.) → discover subnets via the
   `kubernetes.io/role/elb` / `internal-elb` tags already on the VPC
   (`vpc.tf`) → call the ELBv2 API (`CreateLoadBalancer`,
   `CreateTargetGroup`, `CreateListener`) using the IRSA-issued credentials →
   for IP-mode targets, read the Service's `EndpointSlice` objects directly
   to get pod IPs (bypassing the Service/kube-proxy data path entirely — the
   Service object here is only a *configuration source*, not something
   traffic flows through) → `RegisterTargets`/`DeregisterTargets` as pods
   roll.
4. **`TargetGroupBinding` CRD**: even for plain-annotation Services (no raw
   Ingress involved), the controller creates one of these under the hood to
   track pod↔target-group membership continuously, so a rolling deploy only
   costs cheap `RegisterTargets`/`DeregisterTargets` diffs, not a full
   load-balancer re-provision.
5. **Finalizers**: deleting the Service doesn't delete it immediately — a
   `service.k8s.aws/resources` finalizer blocks removal until the controller
   has actually torn down the NLB, target groups, and any security groups it
   created, so you can't accidentally orphan billed AWS resources by
   deleting the Kubernetes object.
6. **Security groups (the part the legacy controller never did at all)**:
   AWS added native security-group support to NLBs in late 2022, and LBC
   uses it by default — it auto-creates a security group for the NLB's
   listeners and a shared "backend" security group applied to target ENIs,
   opening exactly the target port and the health-check port from the LB's
   SG. **This is worth double-checking against this repo**: `eks.tf` sets
   `cluster_security_group_additional_rules = {}` (no custom rules), and
   there's no `node_security_group_additional_rules` either — under the
   *legacy* controller that would have meant nothing opened the NodePort
   range to the internet, i.e. a real gap you'd have had to close by hand.
   LBC's automatic SG management removes that manual step going forward.

---

## Q4. How does IRSA actually authenticate the controller pod to AWS?

Step by step, this is what happens between "pod starts" and "pod can call
`CreateLoadBalancer`":

1. `module.eks` creates an **OIDC identity provider** in IAM, pointed at the
   cluster's own OIDC issuer URL (`module.eks.oidc_provider_arn` /
   `oidc_provider` — already used the same way for `vpc_cni` and
   `ebs_csi_driver` in `eks.tf`).
2. The `ServiceAccount` named `aws-load-balancer-controller` (created by the
   Helm chart per `lbc.tf`) carries the annotation
   `eks.amazonaws.com/role-arn: <aws_iam_role.lb_controller ARN>`.
3. EKS's built-in **Pod Identity Webhook** sees any pod using that
   ServiceAccount at creation time and mutates it: injects the env vars
   `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE`, and mounts a
   **projected, audience-scoped, auto-rotating JWT** at that file path,
   cryptographically signed by the cluster's own OIDC issuer.
4. The AWS SDK inside the controller, on its first AWS API call, reads that
   JWT and calls `sts:AssumeRoleWithWebIdentity`.
5. STS verifies the JWT's signature against the OIDC provider registered in
   step 1, then checks two claims against the role's trust policy
   (`aws_iam_role.lb_controller` in `lbc.tf`): `aud == sts.amazonaws.com` and
   `sub == system:serviceaccount:kube-system:aws-load-balancer-controller`.
   Both conditions are exactly what's hard-coded in that trust policy — if
   either the namespace, service-account name, or audience drifts, this step
   fails closed.
6. STS returns short-lived credentials scoped to whatever
   `aws_iam_policy.lb_controller` allows. No long-lived AWS access keys ever
   exist in the cluster; credentials auto-expire (~1h) and refresh silently,
   and every AWS API call is attributable in CloudTrail back to the specific
   role/service-account pair.

**Aside**: AWS's newer alternative to this whole dance is **EKS Pod
Identity** — it skips OIDC federation entirely, using an
`aws_eks_pod_identity_association` resource plus an in-cluster agent that
talks to EKS's own auth API instead of STS. It wasn't used here specifically
to stay consistent with the IRSA pattern `vpc_cni`/`ebs_csi_driver` already
use in this repo — worth knowing it exists if a broader migration is ever
wanted.

---

## Q5. What's each chunk of the IAM policy actually for?

`iam-policy-aws-load-balancer-controller.json` is broad because it's the
single policy AWS publishes to cover every LBC feature, not something to hand
-trim. Roughly:

- `elasticloadbalancing:Create*` / `Modify*` / `Delete*` — provisioning and
  updating the actual NLB/ALB, target groups, and listeners.
- `elasticloadbalancing:Describe*` — drift detection (reconciling AWS's
  actual state against the cluster's desired state on every resync).
- `ec2:Describe*`, `ec2:CreateSecurityGroup`,
  `ec2:AuthorizeSecurityGroupIngress` — subnet auto-discovery (the
  `kubernetes.io/role/elb` tags) and the automatic backend/LB security-group
  management described in Q3.
- `acm:DescribeCertificate`, `acm:ListCertificates` — resolving the cert ARN
  passed via `aws-load-balancer-ssl-cert` into something it can attach to a
  listener.
- `iam:CreateServiceLinkedRole` (scoped to `elasticloadbalancing.amazonaws.com`)
  — one-time bootstrap of the AWS-managed service-linked role ELB itself
  needs; harmless no-op after the first load balancer ever created in the
  account.
- `wafv2:*`, `shield:*`, `cognito-idp:*` — optional ALB features (WAF
  association, Shield Advanced protection, built-in auth) this setup doesn't
  use, but they ship in the standard policy because the same controller
  binary supports them.
- `tag:GetResources` — ownership/drift reconciliation via AWS resource tags.

This is also why the policy should be **re-downloaded, not hand-maintained**,
whenever the chart version bumps: new controller features occasionally need
new permissions, and a stale hand-copied policy silently breaks them.

---

## Q6. What was the actual failure mode of the `proxy-protocol` annotation?

`service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: "*"` tells the
load balancer to prefix every TCP connection with a small binary PROXY
protocol v2 header carrying the original client IP — a mechanism that only
makes sense when the backend is going to be SNAT'd otherwise (instance-mode
NLB with `externalTrafficPolicy: Cluster`, the legacy setup).

The backend has to be told to *expect* that header, or it just reads the
binary preamble as the start of an HTTP request and misparses it. That
config lives in ingress-nginx's `controller.config.use-proxy-protocol: "true"`
— which was never set in `nginx.yaml`. So the previous config was asking AWS
to prepend a header nginx didn't know to strip, a real, load-bearing bug
waiting to surface as garbled requests or wrong client-IP logging the moment
traffic actually flowed.

Switching to IP-target mode makes the whole annotation unnecessary: the pod
receives the real client IP naturally (Q2), so there's no SNAT to compensate
for and nothing for nginx to parse.

---

## Q7. What exactly was the `ssl-redirect` bug, and why does disabling it fix it without breaking anything?

ingress-nginx decides whether to redirect HTTP→HTTPS by checking **which
listening socket** (`listen ... ssl` vs plain `listen`) a request physically
arrived on — it's derived from the socket, not from any header. It has no
concept of "the load balancer already handled TLS for you."

This setup terminates TLS at the NLB using the ACM cert
(`aws-load-balancer-ssl-cert`), then forwards **plaintext** to nginx
(`targetPorts.https: http` in `nginx.yaml` — both the 80 and 443 listeners on
the LB point at nginx's one plain HTTP port). So *every* request nginx
receives — including ones that arrived at the client as HTTPS — lands on
nginx's plaintext listener. With `ssl-redirect` on (the chart's default),
nginx sees 100% of traffic as "this should be HTTPS" and returns a 308 to
`https://...`. The client reconnects, TLS terminates at the NLB again, and
the plaintext copy lands on nginx's plain listener again → infinite loop (or,
for a client that doesn't follow redirects, just a wrong 308 instead of the
page).

An ALB could paper over this by injecting an `X-Forwarded-Proto` header that
nginx could trust — but NLB is a pure L3/L4 load balancer, it doesn't parse
HTTP at all, so that signal doesn't exist here. `ssl-redirect: "false"` is
the documented fix for exactly this topology ("TLS terminated upstream of
nginx"), and it's safe: nothing downstream needed the redirect to still
happen, since the LB is the only thing accepting client connections in the
first place.

*(Alternative not implemented: terminate TLS at nginx itself instead of the
NLB. That needs a Kubernetes `Secret` holding a private key nginx can read —
and ACM deliberately never lets you export a certificate's private key, so
this path would require swapping ACM for `cert-manager` + a public CA, e.g.
Let's Encrypt via the Route53 DNS-01 solver, since Route53 is already wired
up in this repo. Worth considering later if you want per-host SNI cert
selection or L7 redirect logic in nginx itself, but out of scope for this
change.)*

---

## Q8. Why does `depends_on` matter here if Kubernetes itself doesn't strictly require the ordering?

It's not an admission-time hard dependency the way, say, a validating
webhook would be — `helm install ingress-nginx` will happily succeed even if
the LBC pod doesn't exist yet, because nothing rejects the Service object at
creation time.

The reason for the explicit `depends_on` chain
(`aws_iam_role_policy_attachment.lb_controller` → `helm_release.aws_load_balancer_controller`
→ `helm_release.ingress_nginx`) is **reconciliation timing, not admission
correctness**. If the Service exists before any controller is watching for
it, the NLB simply doesn't get created until LBC starts up and runs its next
resync — usually a matter of seconds, but on a first `terraform apply` this
shows up as "Helm reports the release succeeded, but `kubectl get svc` shows
`<pending>` for the external IP for a while," which is confusing to debug if
you don't know to expect it. The `depends_on` just makes the apply order
match the reconciliation order so that confusion doesn't happen.

---

## Q9. What is EKS Auto Mode, concretely, and how does it relate to this change?

Under the hood, Auto Mode is the *same* load-balancing (and EBS/EFS, and
Karpenter-style node-autoprovisioning) logic AWS already open-sources as LBC
and the other add-on controllers — just built, versioned, and run by AWS as
part of the managed control plane instead of as a `Deployment` you install
and an IRSA role you maintain. You still use the same
`service.beta.kubernetes.io/aws-load-balancer-*` annotation surface; what
disappears is `lbc.tf` itself (no IAM role, no policy file, no Helm release
to manage or upgrade) — AWS keeps that component patched and current for
you.

The reason this migration doesn't jump straight to Auto Mode: it also changes
how *nodes* are managed — `eks_managed_node_groups` (the current SPOT
`t3.medium` group in `eks.tf`) gets replaced by Karpenter `NodeClass`/`NodePool`
objects, which is a materially bigger structural change than "fix how the
load balancer gets created." What's in place now is a **valid, durable
end-state on its own** (LBC is still fully supported, only the *upstream*
project is in maintenance-feature mode, not deprecated) — Auto Mode is a
"consider later" upgrade, not a prerequisite.

---

## Q10. What should be verified before actually applying this?

1. **Security groups — checked, resolved, no action needed.** The concern was
   whether `cluster_security_group_additional_rules = {}` in `eks.tf` (no
   custom rules) leaves nothing open for the NLB to reach nginx. Per the
   controller's own docs
   (https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/security_groups/):
   *"If the LBC auto-creates the frontend security group for a load
   balancer, it automatically adds the security group rules to allow traffic
   from the load balancer to the backend instances/ENIs."* — this repo's
   `nginx.yaml` never sets `aws-load-balancer-security-groups` (no custom
   frontend SG), so LBC is in exactly that auto-created-frontend path: it
   will discover the security group already attached to the pod ENIs (the
   `node_security_group` the `eks` module creates) and add the needed
   ingress rules to it itself, using the `ec2:AuthorizeSecurityGroupIngress`
   permission already present in `iam-policy-aws-load-balancer-controller.json`
   (Q5). This is precisely the capability the legacy in-tree controller
   never had — under it, this *would* have been a real gap requiring a
   manual `node_security_group_additional_rules` entry; under LBC it's
   automatic. Still worth a post-apply `curl` against the NLB DNS name as a
   sanity check, but no Terraform change is required here.
2. **Chart version — checked, bumped.** `helm_release.aws_load_balancer_controller`
   was pinned to chart `1.13.0` (app `v2.13.0`) from published release info,
   not a live lookup. Ran `helm repo add eks https://aws.github.io/eks-charts`
   + `helm search repo eks/aws-load-balancer-controller --versions`: current
   latest is chart `3.5.0` (app `v3.5.0`) — `lbc.tf` now pins that. Note the
   chart went through a **versioning realignment at v3.0.0**: chart `1.x`
   used to track app `v2.x` (e.g. chart `1.17.1` = app `v2.17.1`); starting
   at `3.0.0`, chart version == app version. Checked the v3.0.0 release notes
   for breaking changes before bumping: the only behavioral change is
   Gateway API reaching GA (opt-in, unused here), no new required IAM
   permissions, minimum Kubernetes `1.22+` (this cluster runs `1.36`) — safe
   to take. Re-diffed `iam-policy-aws-load-balancer-controller.json` against
   the live `main` branch source at the same time: byte-identical, so the
   policy in this repo is still current and didn't need re-pulling.
3. **Target health**: still open — this one genuinely requires a live
   cluster. After the NLB comes up, check target group health in the EC2
   console (or `aws elbv2 describe-target-health`) — with IP-mode targets,
   an unhealthy target would point at something LBC's automatic SG
   management from point 1 didn't anticipate, which would be the fastest way
   to catch it.

---

## Q11. Where exactly is the `nlb` vs `nlb-ip` vs `external` split documented?

This came up because an earlier draft of this document cited the wrong pair
of sources — the AWS Load Balancer Controller's own annotation docs, which
only cover `external`/`nlb-ip` (the values that make the *legacy* controller
step aside for LBC). Neither of those is what this repo's Service actually
had before the migration (`aws-load-balancer-type: nlb`, no `-ip` suffix) —
that's a third, separate code path, native to the legacy controller itself,
documented in a different place entirely.

**Primary source — `cloud-provider-aws` docs** (this project *is* "the
legacy in-tree AWS cloud provider" — historically in-tree code inside
`kube-controller-manager`, now maintained out-of-tree under this name, same
job, same annotation surface):
https://cloud-provider-aws.sigs.k8s.io/service_controller/

> "Indicates the type of Load Balancer. The only valid value is `nlb`, this
> means that leaving this field blank or omitting the annotation is
> equivalent to selecting ELB. When selecting `nlb`, the backend protocol is
> automatically derived from the protocol defined in the Kubernetes Service"

**Primary source — the actual code that implements that check**:
https://github.com/kubernetes/cloud-provider-aws/blob/master/pkg/providers/v1/aws_loadbalancer.go
(`isNLB`, ~lines 113–118)

```go
func isNLB(annotations map[string]string) bool {
    if annotations[ServiceAnnotationLoadBalancerType] == "nlb" {
        return true
    }
    return false
}
```

Three values of the same annotation, three different outcomes:

| `aws-load-balancer-type` value | Handled by | Result |
| --- | --- | --- |
| *(annotation absent)* | legacy `cloud-provider-aws` | Classic ELB |
| `nlb` | legacy `cloud-provider-aws` (itself, no LBC needed) | NLB, instance targets |
| `external` / `nlb-ip` (deprecated alias) | legacy controller steps aside → LBC takes over | NLB, ip or instance targets, LBC's full annotation surface |

This repo's Service was on row 2 before the migration (Q1/Q2) — which is
exactly why it had a working NLB despite no LBC ever being installed. It's
on row 3 now (`external` + `nlb-target-type: ip` in `nginx.yaml`).

---
---

# AWS Load Balancer Controller + ingress-nginx — подробный разбор (вопрос-ответ)

Дополнение к `LOAD_BALANCER_MIGRATION.md`. Тот файл описывает *что*
изменилось; этот — объясняет внутреннюю механику, путь пакетов и реальные
сценарии сбоев, которые устраняет каждое изменение.

---

## В1. Что на самом деле создавало load balancer раньше, механически?

Control plane EKS запускает **service controller** как часть
`kube-controller-manager` (это управляется AWS, отдельного пода вы не
увидите). У него одна задача: следить за всеми объектами `Service` в
кластере и для тех, у кого `spec.type: LoadBalancer`, вызывать EC2/ELB API
для создания или обновления AWS load balancer.

Это **legacy / in-tree интеграция AWS cloud provider**. Она появилась
задолго до AWS Load Balancer Controller (LBC) и является именно тем, что
апстрим-инициатива Kubernetes по устареванию in-tree облачных провайдеров
(KEP-2395) пытается вывести из эксплуатации во всех облаках с 2019 года. AWS
по-прежнему поставляет её внутри control plane EKS для обратной
совместимости, но с 2020 года подталкивает пользователей к LBC.

Она читает небольшой, замороженный набор аннотаций
`service.beta.kubernetes.io/aws-load-balancer-*` — тот же *префикс*
аннотаций, который слушает и современный LBC, из-за чего проблема была
незаметна: оба контроллера говорят на одном "диалекте" аннотаций, поэтому
`aws-load-balancer-type: nlb` выглядела как обычная рабочая аннотация. Только
конкретное *значение* (`nlb` против `external`) определяет, какой из двух
контроллеров заберёт себе Service.

**Чего он не делает:** не управляет security group, не поддерживает IP
targets, не поддерживает security group на уровне самого NLB, не позволяет
настраивать атрибуты target group и давно не получает новых возможностей.

---

## В2. Как реально выглядит путь пакета — до и после?

**До (legacy-контроллер, instance targets):**

```
клиент
  │ TCP/TLS
  ▼
NLB (target = ID каждой EC2-ноды, порт = NodePort сервиса)
  │ выбирает любую зарегистрированную ноду — не обязательно ту, где под
  ▼
kube-proxy ноды (iptables/IPVS DNAT)
  │ может уйти через pod-сеть на *другую* ноду
  ▼
под

IP клиента, который видит под: внутренний IP ноды (SNAT от kube-proxy),
а не реальный клиент — если не используется PROXY protocol целиком.
```

**После (AWS Load Balancer Controller, IP targets):**

```
клиент
  │ TCP/TLS
  ▼
NLB (targets = IP подов напрямую, из EndpointSlices)
  │ трафик идёт по VPC прямо на ENI-IP пода — без ноды и kube-proxy
  ▼
под

IP клиента, который видит под: реальный IP клиента, сохранён нативно.
```

Именно это на практике означает "IP target mode убирает хоп": дело не
только в меньшем числе сетевых сегментов — меняется сам *объект*, на
который балансирует трафик load balancer: отдельные поды вместо нод. Это
возможно только потому, что VPC CNI в EKS даёт каждому поду настоящий,
маршрутизируемый в VPC IP-адрес (с overlay-CNI, скрывающим IP подов за NAT,
такая схема бы не заработала).

---

## В3. Как AWS Load Balancer Controller реально устроен внутри?

Это обычный Kubernetes-контроллер (на базе controller-runtime), работающий
как `Deployment` в `kube-system`. Никакой магии сверх стандартной механики
Kubernetes:

1. **Цикл наблюдения**: list-watch за `Service`, `Ingress`, `IngressClass` и
   собственным CRD `TargetGroupBinding` через API-сервер — тот же паттерн
   watch-and-reconcile, что и у любого контроллера, а не вызов вебхука на
   каждый запрос.
2. **Admission-вебхуки**: регистрирует `MutatingWebhookConfiguration` и
   `ValidatingWebhookConfiguration`. Главная задача mutating-вебхука —
   добавлять подам, на которые нацелен трафик напрямую (IP-режим),
   **readiness gate**: под остаётся в состоянии `NotReady`, пока
   контроллер не подтвердит, что под реально зарегистрирован *и* здоров в
   target group AWS — это закрывает гонку, при которой трафик мог бы
   пойти на под до того, как AWS вообще узнает о его существовании, или
   под убирался бы из endpoints сервиса раньше, чем из target group.
3. **Reconcile для Service с аннотацией `aws-load-balancer-type: external`**:
   вычислить желаемое состояние из аннотаций (scheme, target type, TLS
   сертификат, health check, cross-zone и т.д.) → найти подсети по тегам
   `kubernetes.io/role/elb` / `internal-elb`, уже проставленным на VPC
   (`vpc.tf`) → вызвать ELBv2 API (`CreateLoadBalancer`,
   `CreateTargetGroup`, `CreateListener`) с использованием credentials,
   выданных через IRSA → для IP-режима — читать `EndpointSlice` сервиса
   напрямую, чтобы получить IP подов (полностью в обход data path
   Service/kube-proxy — сам объект Service тут только *источник
   конфигурации*, а не то, через что реально идёт трафик) →
   `RegisterTargets`/`DeregisterTargets` при перекате подов.
4. **CRD `TargetGroupBinding`**: даже для Service с аннотациями (без
   отдельного Ingress) контроллер создаёт такой объект под капотом, чтобы
   непрерывно отслеживать связь под↔target group — тогда rolling deploy
   обходится дешёвыми диффами `RegisterTargets`/`DeregisterTargets`, а не
   полным пересозданием load balancer.
5. **Финалайзеры**: удаление Service не удаляет его мгновенно — финалайзер
   `service.k8s.aws/resources` блокирует удаление, пока контроллер
   реально не снесёт NLB, target group и созданные им security group,
   так что случайно "осиротить" оплачиваемые ресурсы AWS, удалив объект
   Kubernetes, не получится.
6. **Security groups (то, чего legacy-контроллер вообще никогда не
   делал)**: AWS добавил нативную поддержку security group для NLB в конце
   2022 года, и LBC использует её по умолчанию — автоматически создаёт
   security group для листенеров NLB и общую "backend" security group для
   ENI таргетов, открывая ровно нужный порт таргета и порт health check со
   стороны SG балансировщика. **Это стоит явно проверить в этом
   репозитории**: в `eks.tf` стоит `cluster_security_group_additional_rules = {}`
   (без кастомных правил), и `node_security_group_additional_rules` тоже
   нигде не задан — при *legacy*-контроллере это могло означать, что
   диапазон NodePort никак не был открыт наружу, то есть реальный пробел,
   который пришлось бы закрывать вручную. Автоматическое управление SG в
   LBC убирает этот ручной шаг на будущее.

---

## В4. Как IRSA реально аутентифицирует под контроллера в AWS?

Пошагово — вот что происходит между "под запустился" и "под может вызвать
`CreateLoadBalancer`":

1. `module.eks` создаёт **OIDC identity provider** в IAM, указывающий на
   собственный OIDC issuer URL кластера (`module.eks.oidc_provider_arn` /
   `oidc_provider` — уже используется точно так же для `vpc_cni` и
   `ebs_csi_driver` в `eks.tf`).
2. `ServiceAccount` с именем `aws-load-balancer-controller` (создаётся
   Helm-чартом согласно `lbc.tf`) несёт аннотацию
   `eks.amazonaws.com/role-arn: <ARN aws_iam_role.lb_controller>`.
3. Встроенный в EKS **Pod Identity Webhook** видит любой под, использующий
   этот ServiceAccount, в момент создания и мутирует его: добавляет
   переменные окружения `AWS_ROLE_ARN` и `AWS_WEB_IDENTITY_TOKEN_FILE`, а
   также монтирует по этому пути **проецируемый, ограниченный по audience,
   автоматически обновляемый JWT**, криптографически подписанный
   собственным OIDC issuer'ом кластера.
4. AWS SDK внутри контроллера при первом вызове AWS API читает этот JWT и
   вызывает `sts:AssumeRoleWithWebIdentity`.
5. STS проверяет подпись JWT по OIDC-провайдеру, зарегистрированному на
   шаге 1, затем сверяет два claim'а с trust policy роли
   (`aws_iam_role.lb_controller` в `lbc.tf`): `aud == sts.amazonaws.com` и
   `sub == system:serviceaccount:kube-system:aws-load-balancer-controller`.
   Оба условия буквально захардкожены в этой trust policy — если
   namespace, имя service account или audience "уедут", этот шаг
   завершится отказом.
6. STS возвращает краткоживущие credentials, ограниченные тем, что
   разрешает `aws_iam_policy.lb_controller`. Долгоживущих AWS access keys в
   кластере нет вообще; credentials истекают (~1 час) и обновляются
   автоматически, а каждый вызов AWS API атрибутируется в CloudTrail к
   конкретной паре роль/service account.

**Отдельно**: более новая альтернатива всей этой схеме у AWS — **EKS Pod
Identity**: она вообще пропускает OIDC-федерацию, используя ресурс
`aws_eks_pod_identity_association` и агент в кластере, который обращается
напрямую к собственному auth API EKS вместо STS+OIDC. Здесь она не
использована специально — чтобы остаться в едином стиле с IRSA, который уже
применяется для `vpc_cni`/`ebs_csi_driver` в этом репозитории; но полезно
знать, что она существует, если когда-нибудь понадобится более широкая
миграция.

---

## В5. За что отвечает каждая часть IAM-политики?

`iam-policy-aws-load-balancer-controller.json` широкая, потому что это
единая политика, которую публикует AWS для покрытия всех возможностей LBC,
а не то, что стоит вручную урезать. Примерно:

- `elasticloadbalancing:Create*` / `Modify*` / `Delete*` — создание и
  обновление самого NLB/ALB, target group и листенеров.
- `elasticloadbalancing:Describe*` — обнаружение расхождений (сверка
  реального состояния AWS с желаемым состоянием кластера при каждой
  синхронизации).
- `ec2:Describe*`, `ec2:CreateSecurityGroup`,
  `ec2:AuthorizeSecurityGroupIngress` — автообнаружение подсетей (теги
  `kubernetes.io/role/elb`) и автоматическое управление security group
  балансировщика/backend'а, описанное в В3.
- `acm:DescribeCertificate`, `acm:ListCertificates` — разрешение ARN
  сертификата, переданного через `aws-load-balancer-ssl-cert`, в то, что
  можно прикрепить к листенеру.
- `iam:CreateServiceLinkedRole` (ограничено
  `elasticloadbalancing.amazonaws.com`) — разовая инициализация
  управляемой AWS service-linked роли, нужной самому ELB; безвредный
  no-op после первого созданного в аккаунте load balancer'а.
- `wafv2:*`, `shield:*`, `cognito-idp:*` — опциональные возможности ALB
  (привязка WAF, защита Shield Advanced, встроенная аутентификация),
  которые здесь не используются, но входят в стандартную политику, так
  как их поддерживает тот же самый бинарник контроллера.
- `tag:GetResources` — сверка владения/расхождений через теги ресурсов
  AWS.

Именно поэтому политику стоит **перекачивать заново, а не поддерживать
вручную** при каждом обновлении версии чарта: новые возможности контроллера
иногда требуют новых прав, а устаревшая скопированная вручную политика
тихо их сломает.

---

## В6. В чём был реальный сценарий сбоя аннотации `proxy-protocol`?

`service.beta.kubernetes.io/aws-load-balancer-proxy-protocol: "*"` просит
балансировщик добавлять перед каждым TCP-соединением небольшой бинарный
заголовок PROXY protocol v2 с реальным IP клиента — механизм, который имеет
смысл только когда backend иначе получил бы SNAT'нутый трафик (NLB в
instance-режиме с `externalTrafficPolicy: Cluster`, как в старой схеме).

Backend должен быть явно настроен *ожидать* этот заголовок, иначе он просто
читает бинарный преамбул как начало HTTP-запроса и не может его разобрать.
Эта настройка — `controller.config.use-proxy-protocol: "true"` в
ingress-nginx — никогда не была установлена в `nginx.yaml`. То есть прежняя
конфигурация просила AWS добавлять заголовок, который nginx не умел
отбрасывать, — реальная, "боевая" ошибка, которая проявилась бы битыми
запросами или неверным client IP в логах, как только через неё пошёл бы
трафик.

Переход на IP target mode делает всю эту аннотацию ненужной: под получает
реальный IP клиента естественным образом (В2), поэтому SNAT компенсировать
не нужно, и nginx нечего разбирать.

---

## В7. В чём именно заключался баг `ssl-redirect` и почему его отключение чинит проблему, ничего не ломая?

ingress-nginx решает, делать ли редирект HTTP→HTTPS, проверяя, **на какой
слушающий сокет** (`listen ... ssl` или обычный `listen`) физически пришёл
запрос — это определяется сокетом, а не каким-либо заголовком. Понятия "load
balancer уже разобрался с TLS за меня" у nginx нет.

В этой схеме TLS терминируется на NLB с помощью сертификата ACM
(`aws-load-balancer-ssl-cert`), а до nginx доходит **незашифрованный**
трафик (`targetPorts.https: http` в `nginx.yaml` — оба листенера
балансировщика, 80 и 443, указывают на один и тот же обычный HTTP-порт
nginx). Поэтому *каждый* запрос, который получает nginx — включая те, что
клиент отправил по HTTPS — попадает на обычный (не-TLS) листенер nginx. При
включённом `ssl-redirect` (значение по умолчанию у чарта) nginx видит 100%
трафика как "это должно быть HTTPS" и отвечает 308 на `https://...`. Клиент
переподключается, TLS снова терминируется на NLB, и незашифрованная копия
снова попадает на тот же обычный листенер nginx → бесконечный цикл (а для
клиента, который не следует редиректам, — просто неверный 308 вместо
страницы).

ALB мог бы замаскировать эту проблему, добавляя заголовок
`X-Forwarded-Proto`, которому nginx мог бы доверять, — но NLB это чистый
L3/L4 балансировщик, он вообще не разбирает HTTP, поэтому такого сигнала
здесь просто не существует. `ssl-redirect: "false"` — это
задокументированное, правильное решение именно для такой топологии ("TLS
терминируется до nginx"), и оно безопасно: ничего ниже по цепочке не
зависело от того, что редирект действительно произойдёт, поскольку сам
балансировщик — единственная точка, принимающая соединения от клиентов.

*(Не реализованная альтернатива: терминировать TLS в самом nginx вместо
NLB. Для этого нужен Kubernetes `Secret` с приватным ключом, который nginx
сможет прочитать — а ACM намеренно никогда не даёт экспортировать приватный
ключ сертификата, так что этот путь потребовал бы заменить ACM на
`cert-manager` + публичный CA, например Let's Encrypt через DNS-01 solver на
базе Route53, который уже настроен в этом репозитории. Стоит рассмотреть
позже, если понадобится выбор сертификата по SNI на хост или L7-логика
редиректов прямо в nginx, но вне рамок текущего изменения.)*

---

## В8. Почему `depends_on` важен здесь, если сам Kubernetes не требует такого порядка строго?

Это не жёсткая зависимость на уровне admission, как, скажем, у validating
webhook — `helm install ingress-nginx` спокойно завершится успехом, даже
если под LBC ещё не существует, потому что ничто не отклоняет объект
Service при создании.

Причина явной цепочки `depends_on`
(`aws_iam_role_policy_attachment.lb_controller` → `helm_release.aws_load_balancer_controller`
→ `helm_release.ingress_nginx`) — это **тайминг реконсиляции, а не
корректность admission**. Если Service существует раньше, чем какой-либо
контроллер начал за ним следить, NLB просто не будет создан, пока LBC не
запустится и не выполнит следующий полный resync — обычно это секунды, но
при первом `terraform apply` это выглядит как "Helm говорит, что релиз
успешен, но `kubectl get svc` какое-то время показывает `<pending>` вместо
внешнего IP", что сбивает с толку, если не знать, что этого стоит ожидать.
`depends_on` просто выравнивает порядок apply с порядком реконсиляции, чтобы
такой путаницы не возникало.

---

## В9. Что такое EKS Auto Mode конкретно и как это связано с этим изменением?

Под капотом Auto Mode — это *та же самая* логика балансировки нагрузки (а
также EBS/EFS и Karpenter-подобного автопровижининга нод), которую AWS уже
публикует как открытый код в виде LBC и других контроллеров-аддонов —
только собранная, версионируемая и запускаемая самим AWS как часть
управляемого control plane, а не как `Deployment`, который устанавливаете и
поддерживаете вы, вместе с IRSA-ролью. Набор аннотаций
`service.beta.kubernetes.io/aws-load-balancer-*` остаётся тем же; исчезает
сам файл `lbc.tf` (не нужна ни IAM-роль, ни файл политики, ни Helm-релиз для
управления и обновления) — этот компонент AWS патчит и обновляет за вас.

Почему эта миграция не сразу прыгает в Auto Mode: он также меняет то, как
управляются *ноды* — `eks_managed_node_groups` (текущая SPOT-группа
`t3.medium` в `eks.tf`) заменяется на объекты Karpenter `NodeClass`/`NodePool`,
что является заметно более крупным структурным изменением, чем "починить,
как создаётся load balancer". То, что сделано сейчас — это **самодостаточное,
устойчивое конечное состояние** (LBC по-прежнему полностью поддерживается,
в режиме "только критические исправления" сейчас *апстрим*-проект, а не
"устарел") — Auto Mode это апгрейд "на подумать позже", а не обязательное
условие.

---

## В10. Что стоит проверить перед реальным `apply`?

1. **Security group — проверено, вопрос закрыт, правок не требуется.**
   Опасение было в том, что `cluster_security_group_additional_rules = {}` в
   `eks.tf` (без кастомных правил) не оставляет NLB никакого способа
   достучаться до nginx. Согласно документации самого контроллера
   (https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/security_groups/):
   *"If the LBC auto-creates the frontend security group for a load
   balancer, it automatically adds the security group rules to allow
   traffic from the load balancer to the backend instances/ENIs"* — в
   `nginx.yaml` этого репозитория нигде не задана
   `aws-load-balancer-security-groups` (своя frontend SG), значит LBC идёт
   ровно по этому пути с автосозданием frontend SG: он сам найдёт security
   group, уже привязанную к ENI подов (это `node_security_group`, который
   создаёт модуль `eks`), и сам добавит в неё нужные ingress-правила — с
   помощью права `ec2:AuthorizeSecurityGroupIngress`, которое уже есть в
   `iam-policy-aws-load-balancer-controller.json` (В5). Это именно та
   возможность, которой никогда не было у legacy in-tree контроллера — при
   нём это действительно был бы реальный пробел, требующий ручной записи в
   `node_security_group_additional_rules`; при LBC это происходит
   автоматически. Проверить `curl`'ом по DNS-имени NLB после `apply`
   всё равно стоит как sanity-check, но менять Terraform здесь не нужно.
2. **Версия чарта — проверено, обновлено.**
   `helm_release.aws_load_balancer_controller` был зафиксирован на чарте
   `1.13.0` (приложение `v2.13.0`) по опубликованной информации о релизах,
   без живой проверки. Выполнил `helm repo add eks https://aws.github.io/eks-charts`
   + `helm search repo eks/aws-load-balancer-controller --versions`: сейчас
   актуальный — чарт `3.5.0` (приложение `v3.5.0`) — `lbc.tf` теперь
   зафиксирован на нём. Важный нюанс: у чарта была **смена схемы
   версионирования на v3.0.0** — раньше чарт `1.x` соответствовал
   приложению `v2.x` (например, чарт `1.17.1` = приложение `v2.17.1`);
   начиная с `3.0.0` версия чарта равна версии приложения. Перед бампом
   версии проверил release notes v3.0.0 на предмет breaking changes:
   единственное поведенческое изменение — Gateway API стал GA (опционально,
   здесь не используется), новых обязательных IAM-прав нет, минимальная
   версия Kubernetes `1.22+` (кластер на `1.36`) — обновление безопасно.
   Заодно сверил `iam-policy-aws-load-balancer-controller.json` построчно с
   актуальным источником в ветке `main` — файлы идентичны побайтово, то
   есть политика в репозитории уже актуальна и перекачивать её заново не
   потребовалось.
3. **Здоровье targets**: по-прежнему открытый пункт — для него реально
   нужен живой кластер. После того как NLB поднимется, проверить здоровье
   target group в консоли EC2 (или `aws elbv2 describe-target-health`) —
   при IP-режиме нездоровый target указывал бы на то, что автоматическое
   управление SG из пункта 1 что-то не учло, и это будет самый быстрый
   способ такое поймать.

---

## В11. Где именно задокументировано разделение `nlb` / `nlb-ip` / `external`?

Этот вопрос возник потому, что в более раннем черновике этого документа была
процитирована не та пара источников — документация по аннотациям самого AWS
Load Balancer Controller, которая описывает только `external`/`nlb-ip`
(значения, при которых *легаси*-контроллер отходит в сторону, уступая LBC).
Ни то, ни другое не было тем, что реально стояло в Service этого репозитория
до миграции (`aws-load-balancer-type: nlb`, без суффикса `-ip`) — это третья,
отдельная ветка кода, нативная для самого легаси-контроллера, задокументированная
совсем в другом месте.

**Первичный источник — документация `cloud-provider-aws`** (этот проект и
есть "legacy in-tree AWS cloud provider" — исторически код был in-tree внутри
`kube-controller-manager`, сейчас поддерживается отдельно под этим именем, но
делает ту же работу с тем же набором аннотаций):
https://cloud-provider-aws.sigs.k8s.io/service_controller/

> "Indicates the type of Load Balancer. The only valid value is `nlb`, this
> means that leaving this field blank or omitting the annotation is
> equivalent to selecting ELB. When selecting `nlb`, the backend protocol is
> automatically derived from the protocol defined in the Kubernetes Service"

**Первичный источник — сам код, который это реализует**:
https://github.com/kubernetes/cloud-provider-aws/blob/master/pkg/providers/v1/aws_loadbalancer.go
(функция `isNLB`, строки ~113–118)

```go
func isNLB(annotations map[string]string) bool {
    if annotations[ServiceAnnotationLoadBalancerType] == "nlb" {
        return true
    }
    return false
}
```

Три значения одной и той же аннотации — три разных исхода:

| Значение `aws-load-balancer-type` | Кто обрабатывает | Результат |
| --- | --- | --- |
| *(аннотации нет)* | legacy `cloud-provider-aws` | Classic ELB |
| `nlb` | legacy `cloud-provider-aws` (сам, без LBC) | NLB, instance targets |
| `external` / `nlb-ip` (устаревший алиас) | легаси отходит в сторону → берёт LBC | NLB, ip или instance targets, полный набор аннотаций LBC |

Service этого репозитория до миграции был на строке 2 этой таблицы (В1/В2) —
именно поэтому у него был рабочий NLB, хотя LBC никогда не был установлен.
Сейчас он на строке 3 (`external` + `nlb-target-type: ip` в `nginx.yaml`).
