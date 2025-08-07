# NGINX Public IngressClass

This module creates a custom IngressClass named `nginx-public` that uses your existing nginx ingress controller with a dedicated IP address from MetalLB.

## Overview

This deployment creates:

- **Custom IngressClass**: `nginx-public` that points to your existing nginx controller
- **Dedicated LoadBalancer Service**: Uses IP `148.187.143.44` from MetalLB `pool-no-auto`
- **No Additional Controller**: Leverages your existing KaaS provider's nginx controller

## What Gets Created

### 1. IngressClass Resource

```yaml
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx-public
spec:
  controller: k8s.io/ingress-nginx
```

### 2. LoadBalancer Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-public-controller
  namespace: ingress-nginx
  annotations:
    metallb.universe.tf/ip-allocated-from-pool: pool-no-auto
spec:
  type: LoadBalancer
  loadBalancerIP: 148.187.143.44
  # Selects your existing nginx controller pods
```

## Usage

Use the `nginx-public` IngressClass in your applications:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mip-epilepsy
spec:
  ingressClassName: nginx-public  # Use the custom class
  rules:
  - host: subdomain.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
  tls:
  - hosts:
    - subdomain.example.com
    secretName: mip-frontend-tls
```

## How It Works

1. **Existing Controller**: Your KaaS provider's nginx controller continues to run normally
2. **Custom IngressClass**: `nginx-public` tells Kubernetes to use the same controller
3. **Dedicated Service**: Routes traffic from `148.187.143.44` to your existing nginx pods
4. **Traffic Flow**: 
   ```
   148.187.143.44 → nginx-public-controller service → existing nginx pods → your applications
   ```

## Deployment

This follows the same pattern as other common applications (like datacatalog):

1. **Discovery**: The `mip-infrastructure` ApplicationSet discovers the `common/nginx-ingress` directory
2. **Application Creation**: It applies the `nginx-ingress.yaml` Application manifest
3. **Project Assignment**: The Application explicitly uses `mip-argo-project-common` project (which has the required permissions)
4. **Resource Deployment**: The Application deploys manifests from `common/nginx-ingress/manifests/`

### Manual Deployment

```bash
# Sync the application
argocd app sync nginx-public-ingress

# Check the application status
argocd app get nginx-public-ingress
```

## Verification

After deployment, verify the setup:

```bash
# Check the IngressClass was created
kubectl get ingressclass nginx-public

# Verify the LoadBalancer service has the correct IP
kubectl get svc -n ingress-nginx nginx-public-controller

# Check that the service points to existing nginx pods
kubectl describe svc -n ingress-nginx nginx-public-controller
```

Expected output:
- IngressClass `nginx-public` exists with controller `k8s.io/ingress-nginx`
- Service `nginx-public-controller` has external IP `148.187.143.44`
- Service endpoints point to your existing nginx controller pods

## Testing

Apply the test application:

```bash
# Apply the test manifests (uses nginx-public IngressClass)
kubectl apply -f common/nginx-ingress/test-ingress.yaml

# Test access
curl -H "Host: test.example.com" http://148.187.143.44
```

## Prerequisites

This implementation requires ArgoCD to have permissions to create IngressClass resources.

## Troubleshooting

### Permission Denied for IngressClass

If you get `ingressclasses.networking.k8s.io is forbidden` or `Resource not found in cluster`:

1. Verify ArgoCD has proper IngressClass permissions:
   ```bash
   # Check application controller (needs create permissions)
   kubectl get clusterrole argocd-application-controller -o yaml | grep -A 3 networking.k8s.io
   
   # Check server (needs read permissions)  
   kubectl get clusterrole argocd-server -o yaml | grep -A 3 networking.k8s.io
   ```
   Both should show `ingressclasses` in the resources list under `networking.k8s.io`.

2. Apply the updated ArgoCD patches:
   ```bash
   cd argo-setup
   kustomize build patches | kubectl apply -f -
   ```

3. Restart ArgoCD components to pick up new permissions:
   ```bash
   kubectl rollout restart statefulset/argocd-application-controller -n argocd-mip-team
   kubectl rollout restart deployment/argocd-server -n argocd-mip-team
   ```

### IP Not Assigned

If the LoadBalancer service shows `<pending>`:

1. Check MetalLB logs:
   ```bash
   kubectl logs -n metallb-system deployment/controller
   ```

2. Verify the IP pool:
   ```bash
   kubectl get ipaddresspools.metallb.io -n metallb-system pool-no-auto -o yaml
   ```

3. Ensure IP is not in use:
   ```bash
   kubectl get svc --all-namespaces -o wide | grep 148.187.143.44
   ```

### IngressClass Not Working

1. Verify your existing nginx controller supports multiple ingress classes:
   ```bash
   kubectl logs -n ingress-nginx deployment/ingress-nginx-controller | grep "ingress class"
   ```

2. Check that the controller is watching for the nginx-public class:
   ```bash
   kubectl describe ingressclass nginx-public
   ```

### Service Not Routing Traffic

1. Check service endpoints:
   ```bash
   kubectl get endpoints -n ingress-nginx nginx-public-controller
   ```

2. Verify the selector matches your nginx pods:
   ```bash
   kubectl get pods -n ingress-nginx --show-labels
   ```

## Integration with Existing Infrastructure

This solution:
- **Preserves** your KaaS provider's nginx setup
- **Adds** a new traffic entry point with dedicated IP
- **Shares** the same nginx controller between both services
- **Allows** you to choose different IPs for different applications

Choose the IngressClass based on your requirements:
- **Default nginx** (KaaS): Use for general applications
- **nginx-public**: Use for applications that need the specific IP `148.187.143.44` 