# ECK Helm Chart for RKE2

This directory contains the ECK Helm chart. It targets managed RKE2 clusters where the Elastic Cloud on Kubernetes (ECK) operator already runs (Rancher installs it under `kube-system`). By default the chart provisions:

- A single-node Elasticsearch cluster plus Kibana.

Optional components (disabled by default):

- Filebeat and Metricbeat DaemonSets that forward cluster logs and metrics.
- The eck-notifier CronJob that pushes Kibana alert summaries to Microsoft Teams and Cisco Webex.

## Prerequisites

- Helm 3 and `kubectl` available locally.
- RKE2 cluster v1.23+ with access to the `elastic-system` namespace.
- ECK operator 2.13+ running cluster-wide (the chart does **not** install it).
- Default StorageClass compatible with the sample workloads (defaults assume `ceph-corbo-cephfs`).
- Namespace prepared for Beats hostPath mounts (needed only if Beats are enabled and Pod Security Admission is enforced):

  ```bash
  kubectl create namespace elastic-system
  kubectl label namespace elastic-system \
    pod-security.kubernetes.io/enforce=privileged \
    pod-security.kubernetes.io/audit=privileged \
    pod-security.kubernetes.io/warn=privileged --overwrite
  ```

- Secret `eck-eck-notifier-secrets` populated with Elasticsearch credentials plus Teams/Webex settings (required only if `alertNotifier.enabled=true`, see [Alert notifier configuration](#alert-notifier-configuration)).
- When Beats are enabled, apply the manual RBAC manifest (the chart does not template Beat RBAC resources):

  ```bash
  kubectl apply -f base/mip-infrastructure/rbac/eck-beats-rbac.yaml
  ```

## Install / upgrade

```bash
helm upgrade --install eck . \
  --namespace elastic-system \
  --create-namespace \
  --skip-crds \
  --wait \
  --timeout 15m
```

> Helm 4 uses server-side apply by default. Because the ECK operator also mutates the CRs, add `--server-side=false` (or configure the same in Argo CD) for conflict-free upgrades.

Supply overrides through `--set`/`-f my-values.yaml` as usual.

## Customising values

All knobs live in `values.yaml`. Common overrides:

- `elasticsearch.*` – adjust resources, replica count, or the StorageClass.
- `kibana.ingress.*` – enable ingress, set hosts/TLS, or keep using port-forward.
- `observability.filebeat.*` / `observability.metricbeat.*` – enable and tune the DaemonSets. Filebeat defaults to 100m CPU, 400Mi request / 600Mi limit.
- `alertNotifier.*` – enable notifier mode, then change the Cron schedule, PVC behaviour, secret names/keys, or Teams/Webex delivery.

## Alert notifier configuration

The chart bundles the `alertNotifier` CronJob so Kibana alerts arrive in Microsoft Teams or Cisco Webex. Adjust the schedule, outputs, and credentials through values. A minimal override file could look like:

```yaml
# alert-notifier-values.yaml
alertNotifier:
  image:
    repository: registry.example.com/eck-notifier
    tag: latest
  schedule: "*/5 * * * *"
  es:
    index: ".internal.alerts-observability.logs.alerts-default-*"
    skipVerify: true
  teams:
    enabled: true
  webex:
    enabled: true
    roomId: ""          # leave empty to pull from the secret
    personEmail: ""
    tokenKey: webexBotToken
    roomIdKey: webexRoomId
  secret:
    create: false
    name: eck-eck-notifier-secrets

kibana:
  ingress:
    enabled: true
    hosts:
      - host: localhost
        path: /
        pathType: Prefix
  http:
    tls:
      selfSignedCertificate:
        disabled: true
  config:
    xpack.security.secureCookies: false
```

Deploy (or upgrade) the chart from the repository root:

```bash
helm upgrade --install eck . -f alert-notifier-values.yaml \
  --namespace elastic-system --create-namespace
```

### Secret

Populate the notifier secret so the CronJob can talk to Elasticsearch and your chat tools:

```bash
kubectl create secret generic eck-eck-notifier-secrets \
  -n elastic-system \
  --from-literal=es-url=https://elasticsearch-sample-es-http.elastic-system.svc:9200 \
  --from-literal=es-user=elastic \
  --from-literal=es-pass="<elastic-password>" \
  --from-literal=teams-webhook="https://outlook.office.com/webhook/..." \
  --from-literal=webexBotToken="<webex-bot-token>" \
  --from-literal=webexRoomId="Y2lzY29zcGFyazovL3VzL1JPT00v..."
```

If you prefer direct Webex messages, leave `webexRoomId` empty and set `alertNotifier.webex.personEmail` instead. Whenever Elasticsearch rotates the `elastic` password, regenerate the secret:

```bash
ES_PASS=$(kubectl get secret elasticsearch-sample-es-elastic-user \
  -n elastic-system \
  -o go-template='{{printf "%s" (index .data "elastic")}}' | base64 -d)

kubectl create secret generic eck-eck-notifier-secrets \
  -n elastic-system \
  --from-literal=es-url=https://elasticsearch-sample-es-http.elastic-system.svc:9200 \
  --from-literal=es-user=elastic \
  --from-literal=es-pass="$ES_PASS" \
  --from-literal=teams-webhook="https://outlook.office.com/webhook/..." \
  --from-literal=webexBotToken="<webex-bot-token>" \
  --from-literal=webexRoomId="Y2lzY29zcGFyazovL3VzL1JPT00v..." \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Persistent state

The CronJob persists alert hashes under `/var/lib/eck-notifier/state.json` (PVC) so it only posts deltas. Override `alertNotifier.state.persistence.*` if you already have a claim or disable persistence for ephemeral deployments.

## Verifying the deployment

```bash
kubectl get elasticsearch -n elastic-system
kubectl get kibana -n elastic-system
# Optional (when enabled)
kubectl get beats.beat.k8s.elastic.co -n elastic-system
kubectl get cronjob eck-eck-notifier -n elastic-system
```

Fetch the autogenerated `elastic` password:

```bash
kubectl get secret elasticsearch-sample-es-elastic-user \
  -n elastic-system \
  -o go-template='{{printf "%s" (index .data "elastic")}}' | base64 -d; echo
```

## Accessing Kibana

Port-forward the service when you only need temporary access:

```bash
kubectl port-forward -n elastic-system svc/kibana-sample-kb-http 5601:5601
```

Then browse to `https://localhost:5601` (accept the self-signed cert warning) and log in with `elastic` plus the password above. To expose Kibana permanently, enable `kibana.ingress.enabled` and provide hosts/TLS values.

## Observability notes

Filebeat autodiscovers pods via hints and forwards container logs. Metricbeat scrapes nodes, pods, containers, volumes, the apiserver, and host metrics. They are disabled by default and can be enabled through `observability.*` in `values.yaml`.

## Uninstalling

```bash
helm uninstall eck -n elastic-system
```

This removes Elasticsearch/Kibana/Beats/notifier workloads but leaves the upstream ECK CRDs installed (so existing CRs keep working). Delete `crds/eck-crds.yaml` manually if you also want the CRDs gone after uninstalling.
