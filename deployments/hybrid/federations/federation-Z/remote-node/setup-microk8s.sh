#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (or sudo) to install MicroK8s and write config." >&2
  exit 1
fi

# Require that the user explicitly set both CIDRs
: "${IPv4_CLUSTER_CIDR:?Error: IPv4_CLUSTER_CIDR must be set. Example: sudo IPv4_CLUSTER_CIDR=10.3.0.0/16 IPv4_SERVICE_CIDR=10.152.185.0/24 $0}"
: "${IPv4_SERVICE_CIDR:?Error: IPv4_SERVICE_CIDR must be set. Example: sudo IPv4_CLUSTER_CIDR=10.3.0.0/16 IPv4_SERVICE_CIDR=10.152.185.0/24 $0}"

echo "==> Using IPv4_CLUSTER_CIDR=${IPv4_CLUSTER_CIDR}"
echo "==> Using IPv4_SERVICE_CIDR=${IPv4_SERVICE_CIDR}"

echo "==> Writing MicroK8s launch configuration with custom IPv4 CIDRs"
mkdir -p /var/snap/microk8s/common
service_gw_ip="$(echo "${IPv4_SERVICE_CIDR}" | awk -F'[./]' '{print $1"."$2"."$3"."$4+1}')"

echo "==> Using extraSANs ${service_gw_ip}"


cat >/var/snap/microk8s/common/.microk8s.yaml <<EOF
---
version: 0.2.0
extraCNIEnv:
  IPv4_CLUSTER_CIDR: "${IPv4_CLUSTER_CIDR}"
  IPv4_SERVICE_CIDR: "${IPv4_SERVICE_CIDR}"
extraSANs:
  - ${service_gw_ip}
addons:
  - name: dns
EOF

echo "==> Installing MicroK8s (channel 1.31/stable)"
snap install microk8s --classic --channel=1.31/stable

echo "==> Waiting for MicroK8s to be ready"
microk8s status --wait-ready

# Create kubectl alias for convenience
echo "==> Creating kubectl alias"
snap alias microk8s.kubectl kubectl 2>/dev/null || true

# Ensure current user can run microk8s commands without sudo
if [[ -n "${SUDO_USER:-}" ]]; then
  echo "==> Adding $SUDO_USER to microk8s group"
  usermod -a -G microk8s "$SUDO_USER" || true
fi

# Export kubeconfig for current user if HOME is set and writable
if [[ -n "${SUDO_USER:-}" ]]; then
  user_home=$(eval echo ~"${SUDO_USER}")
else
  user_home="$HOME"
fi

if [[ -n "$user_home" && -d "$user_home" ]]; then
  echo "==> Exporting kubeconfig to $user_home/.kube/config"
  mkdir -p "$user_home/.kube"
  microk8s.kubectl config view --raw > "$user_home/.kube/config"
  chown -R "${SUDO_USER:-root}": "$user_home/.kube"
fi

echo "==> Verifying CIDRs"
echo -n "Kubernetes service IP: "
microk8s.kubectl get svc kubernetes -o jsonpath='{.spec.clusterIP}' && echo || true

echo -n "Calico Pod CIDR (from DS env): "
microk8s.kubectl -n kube-system get daemonset calico-node \
  -o jsonpath="{.spec.template.spec.containers[?(@.name=='calico-node')].env[?(@.name=='CALICO_IPV4POOL_CIDR')].value}" && echo || true

echo "==> Detecting Calico version"
CALICO_VERSION=$(microk8s.kubectl -n kube-system get daemonset calico-node \
  -o jsonpath='{.spec.template.spec.containers[?(@.name=="calico-node")].image}' | \
  grep -oP 'v\d+\.\d+\.\d+' )
echo "==> Found Calico version: ${CALICO_VERSION}"

echo "==> Installing Calico API server (required for Submariner)"
# Create the namespace declaratively to avoid apply warning
microk8s.kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: calico-apiserver
EOF
microk8s.kubectl apply -n calico-apiserver -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/apiserver.yaml"

echo "==> Generating TLS certificate for Calico API server"
openssl req -x509 -nodes -newkey rsa:4096 \
  -keyout /tmp/apiserver.key -out /tmp/apiserver.crt -days 365 -subj "/" \
  -addext "subjectAltName = DNS:calico-api.calico-apiserver.svc" 2>/dev/null

microk8s.kubectl -n calico-apiserver create secret generic calico-apiserver-certs \
  --from-file=apiserver.key=/tmp/apiserver.key \
  --from-file=apiserver.crt=/tmp/apiserver.crt \
  --dry-run=client -o yaml | microk8s.kubectl apply -f -

echo "==> Patching APIService to trust Calico certificate"
microk8s.kubectl patch apiservice v3.projectcalico.org --type=merge \
  -p "{\"spec\":{\"caBundle\":\"$(microk8s.kubectl get secret -n calico-apiserver calico-apiserver-certs -o go-template='{{ index .data "apiserver.crt" }}')\"}}"

rm -f /tmp/apiserver.key /tmp/apiserver.crt

echo "==> Waiting for Calico API server to be ready"
sleep 60
microk8s.kubectl -n calico-apiserver wait --for=condition=Ready pod -l apiserver=true --timeout=120s 

echo ""
echo "==> Done! MicroK8s is installed and configured."
echo "==> IMPORTANT: Run this command to activate microk8s group:"
echo "    newgrp microk8s"
echo ""
echo "Then verify with:"
echo "    kubectl get nodes"