# Submariner Remote Node Setup for Federation-Z

This guide installs MicroK8s with your chosen IPv4 CIDRs, extracts broker credentials from the public cluster (self-signed CA supported), and installs the Submariner operator via Helm.

## 1) Prepare broker credentials (on PUBLIC cluster)

On the PUBLIC cluster, find the service account secret created by subctl. The secret name will be like `submariner-broker-submariner-k8s-broker-client-token` in the `submariner-k8s-broker` namespace.

```bash
# On PUBLIC cluster (broker)
# Extract token (decode from base64 - Helm chart expects plain text token)
kubectl -n submariner-k8s-broker get secret submariner-broker-submariner-k8s-broker-client-token -o jsonpath='{.data.token}' | base64 -d > broker-token.txt

# Extract CA certificate (keep as base64 - Helm chart expects base64-encoded CA)
kubectl -n submariner-k8s-broker get secret submariner-broker-submariner-k8s-broker-client-token -o jsonpath='{.data.ca\.crt}' > broker-ca-base64.txt

# Extract IPSec PSK from the main cluster's submariner-operator namespace
kubectl -n submariner-operator get secret submariner-ipsec-psk -o jsonpath='{.data.psk}' > broker-psk.txt

# Copy these 3 files to the REMOTE node via scp or other secure means (broker-token.txt, broker-ca-base64.txt, broker-psk.txt)
```

**Security note**: These files contain sensitive credentials. Transfer them securely (scp, rsync over SSH) and delete them after use.

## 2) Bootstrap tools on the fresh Ubuntu VM

Run this once on a clean machine to install required tooling (curl, jq, helm, subctl). Note: kubectl will be provided by MicroK8s in the next step.

```bash
sudo ./setup-tools.sh
```

What it does:
- Installs curl, jq, ca-certificates
- Installs Helm (snap classic)
- Installs subctl (latest) to /usr/local/bin
- Ensures /snap/bin is in PATH

**Important**: kubectl is NOT installed here - it will be aliased from microk8s.kubectl after the next step.

## 3) Install MicroK8s with custom IPv4 CIDRs

Use the helper script to set `IPv4_CLUSTER_CIDR` and `IPv4_SERVICE_CIDR`, then install MicroK8s and wait for readiness.

```bash
# Example (adjust the CIDRs if needed)
sudo IPv4_CLUSTER_CIDR=10.3.0.0/16 IPv4_SERVICE_CIDR=10.152.185.0/24 ./setup-microk8s.sh
```

What the script does:
- Writes `/var/snap/microk8s/common/.microk8s.yaml` with your CIDRs
- Installs MicroK8s: `snap install microk8s --classic --channel=1.31/stable`
- Waits for MicroK8s to be ready and exports kubeconfig
- Creates kubectl alias (microk8s.kubectl → kubectl)
- Adds your user to the microk8s group
- Verifies Pod/Service CIDRs
- Installs Calico API server (required for Submariner to detect network settings)
- Generates TLS certificates and patches the APIService

If you prefer manual steps, see `subctl-procedure.md` (MicroK8s section).

**After the script completes**:
1. Run `newgrp microk8s` to activate group membership (or log out/in)
2. Verify: `kubectl get nodes`

The script takes several minutes (MicroK8s initialization + Calico API server).

## 4) Helm Installation (Recommended for Production)

### Prerequisites
- MicroK8s installed with your custom CIDRs (via the script above)
- Broker credentials files (broker-token.txt, broker-ca-base64.txt, broker-psk.txt) transferred to remote node
- Helm CLI installed

### Installation Steps

1. Add Submariner Helm repository:

```bash
helm repo add submariner-latest https://submariner-io.github.io/submariner-charts/charts
helm repo update
```

2. Install Submariner operator with credentials:

**Note**: The chart expects the token and PSK as plain text, and the CA certificate as **base64-encoded** (not decoded PEM).

```bash
# Label node for gateway (replace NODE_NAME with your actual node name)
microk8s.kubectl label node NODE_NAME submariner.io/gateway=true

# Install with credentials from files
helm install submariner-operator submariner-latest/submariner-operator \
  --namespace submariner-operator \
  --version 0.21.0 \
  --create-namespace \
  --set-string broker.token="$(cat broker-token.txt)" \
  --set-string broker.ca="$(cat broker-ca-base64.txt)" \
  --set-string ipsec.psk="$(cat broker-psk.txt)" \
  --values submariner-values.yaml
```

Alternative (if you prefer to store credentials in a Kubernetes secret first):
```bash
kubectl create namespace submariner-operator
kubectl -n submariner-operator create secret generic broker-secret \
  --from-literal=token="$(cat broker-token.txt)" \
  --from-literal=ca="$(cat broker-ca-base64.txt)" \
  --from-literal=psk="$(cat broker-psk.txt)"

# Then extract and use in helm install
helm install submariner-operator submariner-latest/submariner-operator \
  --version 0.21.0 \

  --namespace submariner-operator \
  --create-namespace \
  --set-string broker.token="$(kubectl -n submariner-operator get secret broker-secret -o jsonpath='{.data.token}' | base64 -d)" \
  --set-string broker.ca="$(kubectl -n submariner-operator get secret broker-secret -o jsonpath='{.data.ca}' | base64 -d)" \
  --set-string ipsec.psk="$(kubectl -n submariner-operator get secret broker-secret -o jsonpath='{.data.psk}' )" \
  --values submariner-values.yaml
```

3. Verify installation:
```bash
kubectl get pods -n submariner-operator
subctl show connections
```

4. **Cleanup credentials** (important for security):
```bash
# Securely wipe sensitive files after use
shred -u broker-token.txt broker-ca-base64.txt broker-psk.txt

# If credentials were included inline, securely delete submariner-values.yaml as well
[ -f submariner-values.yaml ] && shred -u submariner-values.yaml
```

## Option 2: subctl Installation (Fallback)

If Helm installation encounters issues, fall back to tested subctl method:

```bash
# Follow steps from subctl-procedure.md "Setup on Private Remote Cluster (MicroK8s)"
subctl join broker-info.subm --clusterid federation-z-remote --check-broker-certificate=false
```

## Verification

Test connectivity from remote cluster:
```bash
kubectl -n test run tmp-shell --rm -it --image quay.io/submariner/nettest -- /bin/bash
# Inside pod:
curl nginx.test.svc.clusterset.local:8080
```

## Troubleshooting

### Certificate Errors ("x509: certificate signed by unknown authority")

If you see certificate errors in the `submariner-operator` logs or `ServiceExport` status, it means the broker CA was not correctly configured during installation.

1.  **Verify the CA** using the `openssl` command in the "Verify the CA" section above.

```bash
# On the REMOTE node (after copying the files)
# 1. Decode the CA to a temporary file
base64 -d broker-ca-base64.txt > broker-ca.crt

# 2. Verify connection to the broker API server
# Replace example.com:6443 with your broker address if different
openssl s_client -connect example.com:6443 -CAfile broker-ca.crt -showcerts < /dev/null

# You should see "Verify return code: 0 (ok)" at the end.
# If you see "Verify return code: 19 (self-signed certificate...)", the CA is incorrect or missing.
```

2.  **Update the installation** with the correct CA:

```bash
helm upgrade submariner-operator submariner-latest/submariner-operator \
  --namespace submariner-operator \
  --reuse-values \
  --version 0.21.0 \
  --set-string broker.ca="$(cat broker-ca-base64.txt)"
```
