# Exareme2 Overlay Patches for Federation-A

## Current Status

### 🟢 Active Patches (Currently Applied)
- ✅ `exareme2-pvc-patch.yaml` - **TESTING**

### 📚 Example Patches (Commented Out)
These are kept as examples and can be enabled when needed:
- 📄 `exareme2-deployment-patch.yaml` - Main deployment resources, env vars, affinity
- 📄 `exareme2-service-patch.yaml` - LoadBalancer configuration
- 📄 `exareme2-configmap-patch.yaml` - Custom configuration
- 📄 `exareme2-hpa.yaml` - Horizontal Pod Autoscaler (5-20 replicas)

## What's Being Applied

### exareme2-pvc-patch.yaml (ACTIVE)

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: csv-data-exareme2-localworker-0
  namespace: federation-a
spec:
  resources:
    requests:
      storage: 8Gi  # Increase from 4Gi to 8Gi
  storageClassName: ceph-corbo-cephfs
  accessModes:
    - ReadWriteMany
```

**Effect**: When the Helm chart creates the `exareme2-worker` Deployment, this overlay will:
1. Set replicas to **5** (regardless of Helm default)
2. Set CPU limits to **1.5 cores** per pod
3. Set Memory limits to **3Gi** per pod
4. Add custom environment variables (8 worker threads, 40% max memory)
5. Schedule on nodes labeled with `federation: federation-a`

## Enabling Additional Patches

To enable any of the example patches, edit `kustomization.yaml`:

```yaml
resources:
  # Uncomment the patches you want to enable:
  - exareme2-deployment-patch.yaml  # ← Remove the # to enable
  - exareme2-pvc-patch.yaml
  # - exareme2-service-patch.yaml   # ← Still commented out
```

## Testing Changes

Before enabling a patch in ArgoCD:

```bash
# Test the overlay renders correctly
cd overlays/exareme2
kubectl kustomize .

# Dry-run apply to check for errors
kubectl kustomize . | kubectl apply --dry-run=client -f -
```

## Common Scenarios

### Scenario 1: Adjust worker resources
On a patch that does not use statefulsets (immutable), edit resources in this way:
```yaml
resources:
  limits:
    cpu: 2000m    # Increase from 1500m to 2 cores
    memory: 4Gi   # Increase from 3Gi to 4GB
```

### Scenario 2: Enable autoscaling for main deployment
Uncomment in `kustomization.yaml`:
```yaml
resources:
  - exareme2-hpa.yaml  # Enables autoscaling 5-20 replicas
```

### Scenario 3: Change service to LoadBalancer
Uncomment in `kustomization.yaml`:
```yaml
resources:
  - exareme2-service-patch.yaml  # Changes to LoadBalancer
```

### Scenario 4: Increase storage
Uncomment in `kustomization.yaml`:
```yaml
resources:
  - exareme2-pvc-patch.yaml  # Increases to 500Gi
```

## Verification in Cluster

After ArgoCD syncs, verify the worker configuration:

```bash
# Check worker deployment
kubectl get deployment exareme2-worker -n federation-a -o yaml

# Check replicas
kubectl get deployment exareme2-worker -n federation-a -o jsonpath='{.spec.replicas}'

# Check resources
kubectl get deployment exareme2-worker -n federation-a \
  -o jsonpath='{.spec.template.spec.containers[0].resources}' | jq .

# Check environment variables
kubectl get deployment exareme2-worker -n federation-a \
  -o jsonpath='{.spec.template.spec.containers[0].env[*].name}'

# Check actual pods
kubectl get pods -n federation-a -l app=exareme2-worker
```

## Architecture

```
Helm Chart (upstream)
      ↓
Base Worker Deployment
   replicas: 3 (example)
   resources: minimal
      ↓
Server-Side Apply Merge
      ↓
exareme2-pvc-patch.yaml
   storage: 8Gi            ← OVERRIDES
      ↓
Final Worker Deployment in K8s
   ✅ 5 replicas
   ✅ 1.5 CPU / 3Gi RAM per pod
   ✅ Custom env vars (8 threads, 40% max memory)
   ✅ Scheduled on specific nodes
```

## Important Notes

1. **Patches merge, not replace** - Only specified fields are overridden
2. **Container name must match** - The `name: worker` must match the chart's container name
3. **Server-side apply** - Kubernetes intelligently merges the changes
4. **ArgoCD sync-wave** - Overlay applies after base (wave 2 > wave 1)
5. **All patches are examples** - Customize for your actual needs!

## Rollback

To remove all overlays:

```yaml
# In kustomization.yaml, comment out all resources:
resources:
  # - exarexareme2-pvc-patch.yaml
```

Or delete the overlay application:
```bash
kubectl delete application federation-a-exareme2-overlay -n argocd-mip-team
```

## Next Steps

1. Worker patch is currently being tested
2. Monitor worker pods: `kubectl top pods -n federation-a -l app=exareme2-worker`
3. Adjust resources based on actual usage
4. Enable other patches as needed
5. Document any custom patches you create

## Questions?

See:
- `../README.md` - Complete federation customization guide

