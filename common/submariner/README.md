# MIP Submariner Deployment

Deploys Submariner for multi-cluster connectivity in MIP infrastructure using official Submariner Helm charts.

## Overview

This deployment uses:
- Official `submariner-k8s-broker` Helm chart for broker components
- Official `submariner-operator` Helm chart for cluster connectivity
- Custom values files for environment-specific configuration
- Kustomize for additional customization when needed

## Prerequisites

- Kubernetes 1.23+ (both clusters)
- Helm 3.8+ (on nodes where deploying manually)
- Calico CNI with VXLAN encapsulation
- Non-overlapping cluster CIDRs
- LoadBalancer service support (or MetalLB) for broker cluster
- Argo CD installed on broker cluster

## Manual Installation guide for testing (we use argocd normally)

### 1. Deploy Broker and Operator (Public Cluster via Argo CD)

```bash
# Apply the Argo CD Applications
kubectl apply -f submariner.yaml

# Sync the applications
argocd app sync submariner-broker
argocd app sync submariner-operator
```

### 2. Get Broker Info

After broker deployment, extract connection details for remote cluster:

```bash
# Get broker API server
kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}'

# Create service account token
kubectl create token submariner-broker -n submariner-k8s-broker --duration=87600h

# Get CA certificate
kubectl get secret -n submariner-k8s-broker <secret-name> -o jsonpath='{.data.ca\.crt}' | base64 -d
```

Update these values in `deployments/hybrid/federations/federation-Z/remote-node/submariner-values.yaml`.

### 3. Deploy to Remote Cluster

See `../../deployments/hybrid/federations/federation-Z/remote-node/README.md`

## Configuration

### Key Values

All values are set in `values-public-cluster.yaml`:

- `submariner-operator.submariner.clusterID`: Unique identifier for cluster
- `submariner-operator.submariner.clusterCIDR`: Pod network CIDR
- `submariner-operator.submariner.serviceCIDR`: Service network CIDR
- `submariner-k8s-broker.globalnet.enabled`: Enable for overlapping CIDRs (false by default)

See official chart documentation for all available options:
- [submariner-k8s-broker chart](https://github.com/submariner-io/submariner-charts/tree/main/submariner-k8s-broker)
- [submariner-operator chart](https://github.com/submariner-io/submariner-charts/tree/main/submariner-operator)

## Verification

```bash
# Check broker pods
kubectl get pods -n submariner-k8s-broker

# Check operator pods  
kubectl get pods -n submariner-operator

# Check connections (after remote cluster joins)
subctl show connections

# Test service discovery
kubectl run test --rm -it --image=busybox -- nslookup test.federation-z.svc.clusterset.local
```

## Customization with Kustomize

For settings not exposed by Helm charts, use Kustomize patches in `kustomization.yaml`.

Example: Setting a specific LoadBalancer IP (see `patches/` directory).

## Troubleshooting

See project documentation for detailed troubleshooting guide.


