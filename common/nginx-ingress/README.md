# nginx-ingress (public edge)

This kustomize set deploys a **second ingress-nginx controller** that publishes a **different LoadBalancer IP** from your default one.

- Ingresses using your existing class (e.g. `nginx`) keep **IP A**.  
- Ingresses using **`nginx-public`** get **IP B**.

It’s portable (cloud LBs or MetalLB), avoids filesystem mounts, and uses unique flags/labels so it won’t clash with anything else.

> **RBAC is applied separately:**  
> `base/mip-infrastructure/rbac/nginx-public-rbac.yaml`  
> Apply that before (or together with) this kustomization.

---

## What’s here

```
common/nginx-ingress/
├── kustomization.yaml
├── nginx-public-deployment.yaml      # second ingress-nginx controller
├── nginx-public-ingressclass.yaml    # IngressClass: nginx-public
└── nginx-public-service.yaml         # LoadBalancer Service for IP B
```

The RBAC this controller needs lives outside this folder:  
`base/mip-infrastructure/rbac/nginx-public-rbac.yaml`.

---

## How “two IPs” is achieved

This controller uses **unique identifiers**:

- `--controller-class = k8s.io/ingress-nginx-public`
- `--ingress-class   = nginx-public`
- `--election-id     = ingress-nginx-public-leader`
- `--publish-service = <namespace>/nginx-public-controller` (the Service that owns **IP B**)

Ingresses that set `spec.ingressClassName: nginx-public` will be reconciled here and get **IP B** in their `.status.loadBalancer`.

---

## Quick start

```bash
# 1) Apply RBAC (required)
kubectl apply -f base/mip-infrastructure/rbac/nginx-public-rbac.yaml

# 2) Apply this kustomization
kubectl apply -k common/nginx-ingress/

# 3) Watch the controller come up
kubectl -n ingress-nginx get pods -l app.kubernetes.io/instance=nginx-public -w

# 4) Verify the public LoadBalancer IP (IP B)
kubectl -n ingress-nginx get svc nginx-public-controller -o wide

# 5) Point an Ingress at it
# Preferred: set the spec field in the manifest:
# spec:
#   ingressClassName: nginx-public
# OR patch an existing object (compat annotation):
kubectl -n <ns> annotate ingress/<name> kubernetes.io/ingress.class=nginx-public --overwrite

# 6) Confirm the Ingress shows IP B
kubectl get ingress -A -o wide | grep nginx-public
```

---

## Files (overview)

### `nginx-public-ingressclass.yaml`

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx-public
spec:
  controller: k8s.io/ingress-nginx-public   # must match --controller-class
```

### `nginx-public-service.yaml` (your **public** LoadBalancer)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-public-controller
  namespace: ingress-nginx
  # Add provider-specific annotations here as needed.
  # For MetalLB you can request a pool or pin an IP:
  # annotations:
  #   metallb.io/address-pool: pool-no-auto
spec:
  type: LoadBalancer
  externalTrafficPolicy: Local
  # MetalLB only: pin a specific address if desired
  # loadBalancerIP: 203.0.113.44
  ports:
    - { name: http,  port: 80,  targetPort: http }
    - { name: https, port: 443, targetPort: https }
  selector:
    app.kubernetes.io/name: nginx-public
    app.kubernetes.io/instance: nginx-public
    app.kubernetes.io/component: controller
```

### `nginx-public-deployment.yaml` (the second controller)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-public-controller
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: nginx-public
    app.kubernetes.io/instance: nginx-public
    app.kubernetes.io/component: controller
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: nginx-public
      app.kubernetes.io/instance: nginx-public
      app.kubernetes.io/component: controller
  template:
    metadata:
      labels:
        app.kubernetes.io/name: nginx-public
        app.kubernetes.io/instance: nginx-public
        app.kubernetes.io/component: controller
    spec:
      serviceAccountName: nginx-public
      containers:
        - name: controller
          image: registry.k8s.io/ingress-nginx/controller:v1.13.0
          imagePullPolicy: IfNotPresent
          args:
            - /nginx-ingress-controller
            - --publish-service=$(POD_NAMESPACE)/nginx-public-controller
            - --election-id=ingress-nginx-public-leader
            - --controller-class=k8s.io/ingress-nginx-public
            - --ingress-class=nginx-public
            - --watch-ingress-without-class=false
          env:
            - name: POD_NAMESPACE
              valueFrom: { fieldRef: { fieldPath: metadata.namespace } }
            - name: POD_NAME
              valueFrom: { fieldRef: { fieldPath: metadata.name } }
          ports:
            - { name: http,  containerPort: 80 }
            - { name: https, containerPort: 443 }
          livenessProbe:
            httpGet: { path: /healthz, port: 10254 }
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet: { path: /healthz, port: 10254 }
            initialDelaySeconds: 10
            periodSeconds: 10
      nodeSelector:
        kubernetes.io/os: linux
      terminationGracePeriodSeconds: 300
```

> If you rename the IngressClass or Service, update these flags to match:  
> `--ingress-class=<your-class>` • `--controller-class=<your-controller-string>` • `--publish-service=$(POD_NAMESPACE)/<your-service>` • and the `IngressClass.spec.controller`.

---

## Configuration notes

### Service (LoadBalancer)

- **MetalLB**: keep `loadBalancerIP` to pin a fixed address or use `metallb.io/address-pool` to allocate from a pool.  
- **Cloud LBs**: remove `loadBalancerIP` and add provider annotations if required.

### Optional: PROXY protocol

If your LB/MetalLB speaks PROXY protocol:

- annotate the **Service** (MetalLB): `metallb.io/proxy-protocol: "true"`  
- set `use-proxy-protocol: "true"` in a controller ConfigMap (if you add one)

---

## RBAC (applied separately)

This controller needs RBAC that allows it to:

- read common cluster objects (services, endpoints, pods, namespaces, …)
- **update/patch** `ingresses/status`
- leader election using a **Lease** in `ingress-nginx`:
  - **must** be able to **create** `leases` (cannot restrict `create` by name)
  - may then `get/list/watch/update/patch` the specific lease object (e.g., `ingress-nginx-public-leader`)

Apply from:  
`base/mip-infrastructure/rbac/nginx-public-rbac.yaml`

---

## Verification & troubleshooting

```bash
# Controller is running
kubectl -n ingress-nginx get pods -l app.kubernetes.io/instance=nginx-public

# Lease exists & updates
kubectl -n ingress-nginx get lease | grep ingress-nginx-public-leader
kubectl -n ingress-nginx logs deploy/nginx-public-controller --tail=100 | egrep -i 'acquired lease|became leader'

# Publish-service has an external IP (IP B)
kubectl -n ingress-nginx get svc nginx-public-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}{"\n"}'

# Ingresses using nginx-public show IP B
kubectl get ingress -A -o wide | grep nginx-public
```

**Common pitfalls**

- `forbidden ... cannot create resource "leases"` → RBAC must grant `create` on `leases` (unscoped by name) **and** specific-name access for `get/list/watch/update/patch`.
- `Ignoring ingress because of error while validating ingress class` → `IngressClass.spec.controller` must equal the controller’s `--controller-class`.
- Wrong IP in Ingress status → ensure `--publish-service` points at `ingress-nginx/nginx-public-controller` and that Service has an external IP.
- Service never gets an IP → check LB annotations/quotas (cloud) or MetalLB pools/selectors.
- TLS warnings “Using default certificate” → expected until the referenced TLS Secrets match your hostnames.

---

## Upgrading the controller

Edit the image tag in `nginx-public-deployment.yaml`:

```yaml
image: registry.k8s.io/ingress-nginx/controller:v1.13.0
```

Apply and watch the rollout:

```bash
kubectl apply -k common/nginx-ingress/
kubectl -n ingress-nginx rollout status deploy/nginx-public-controller
```

---

## FAQ

**Do I need a second controller for two different status IPs?**  
Yes. One controller can serve multiple classes, but it only publishes one IP (from its `--publish-service`).

**Do I need a ConfigMap?**  
Only if you want to tweak NGINX settings. You can add  
`--configmap=$(POD_NAMESPACE)/nginx-public-controller` later and create a matching ConfigMap.

**Can I enable PROXY protocol?**  
Yes—see “Optional: PROXY protocol” above.