# Ingress vs Service: почему LoadBalancer создаётся сам по себе

## Вопрос
В сетапе создаётся Ingress, но Service типа `LoadBalancer` нигде явно не
объявлен — а он всё равно появляется. Как так?

## Разница между объектами
- **Service** — L4-абстракция внутри кластера: стабильный IP/DNS для набора
  подов (по `selector`), балансирует TCP/UDP. `type: LoadBalancer` у Service —
  это просто команда облаку поднять внешний балансировщик перед этим Service.
- **Ingress** — L7-объект: правила роутинга по host/path (например,
  "myapp.example.com/ping → Service X"). Сам по себе Ingress ничего не
  создаёт и бесполезен без **Ingress controller**, который его читает и
  настраивает реальный роутинг/балансировщик.

## Как это устроено в этом репозитории
- `k8s/manifests/app.yaml`: `Service photoapp` — `type: ClusterIP`, внешний
  LB сам по себе не создаёт.
- Там же Ingress `photoapp` использует `ingressClassName: nginx` — значит его
  обрабатывает **ingress-nginx**, а не AWS Load Balancer Controller.
- `environments/develop/nginx.tf` поднимает чарт `ingress-nginx` через Helm.
  Этот чарт **сам создаёт свой Service типа LoadBalancer**
  (`ingress-nginx-controller`) — это стандартная часть чарта, объявлять его
  руками не нужно. AWS-аннотации (ACM-сертификат и т.п.) вешаются на этот
  Service через `set` в nginx.tf.

## Цепочка трафика
```
Интернет → LB (создан Service внутри чарта ingress-nginx)
         → под ingress-nginx-controller
         → смотрит правила Ingress (host/path)
         → шлёт на ClusterIP Service photoapp
         → под photoapp
```

## Альтернатива: AWS Load Balancer Controller напрямую
Если бы Ingress использовал ALB-аннотации (`kubernetes.io/ingress.class: alb`
или `IngressClass` с контроллером `ingress.k8s.aws/alb`) вместо
`ingressClassName: nginx`, то AWS Load Balancer Controller (тоже
развёрнутый в этом репо, см. `lbc.tf`) создал бы отдельный ALB **прямо из
самого Ingress**, без промежуточного Service типа LoadBalancer. Это другая,
AWS-специфичная модель маршрутизации.
