---
name: add-app
description: Use when adding a new app under main/<project>/ — scaffold the chart, register it in the project's applications list, and validate it against this repo's ArgoCD + Helm conventions.
---

# Add a New App

This repo is **ArgoCD App-of-Apps + plain Helm only**. Most apps are small Helm charts that depend on `app-template` `5.2.1`; a few are plain-manifest charts that render raw CRDs/resources from `templates/`. Mirror a recent real chart instead of inventing structure.

| Reference app | Shows |
| --- | --- |
| `main/homelab/mosquitto/` | Inline `app-template.externalSecrets`, ConfigMap + secret mounts, `tag@sha256` image pinning |
| `main/homelab/home-assistant/` | Standalone `templates/*-secret.yaml`, direct `dataFrom` from 1Password, route exposure, storage-node avoidance |
| `main/homelab/external-route/` | Plain-manifest chart pattern with raw `HTTPRoute`/Envoy resources and schema headers |

## 1. Gather the app details first

Before creating files, confirm these repo-specific choices:

- **Project + namespace**: usually `main/homelab/<app>` in `default`, or `main/ai/<app>` in `ai`.
- **Chart type**:
  - use **`app-template`** for a normal Deployment/Service/PVC/route app;
  - use a **plain-manifest chart** when you need to template raw CRDs/resources yourself (for example `main/ai/litellm/` or `main/homelab/external-route/`).
- **Secret source**: this repo uses **ExternalSecret + 1Password Connect** only (`ClusterSecretStore` `onepassword-connect`).
- **1Password field naming**: current app charts usually pull **all fields** from one item with `dataFrom.extract.key`, so field names in 1Password must already match what the app expects.
- **Image pin**: prefer `tag: <version>@sha256:<digest>` in one field.
- **Security context**: do not assume `1001` blindly — several apps use `1000`, `1001`, or `10000` depending on the image.
- **Node affinity**: only add the `storage`-node avoidance rule for I/O-sensitive apps that should stay off Longhorn/storage nodes.
- **Exposure**: for web UIs, use Envoy Gateway via `HTTPRoute`/`route` with `parentRefs` to `internal` and/or `public` in `kube-system`.
- **Backups**: do **not** invent per-app VolSync/Kopia wiring; there is no established per-app backup-registration pattern in this repo yet.

## 2. Create the chart files

### Option A: normal app-template chart

Create `main/<project>/<app>/Chart.yaml`:

```yaml
apiVersion: v2
name: <app>
version: 1.0.0
dependencies:
  - name: app-template
    version: 5.2.1
    repository: oci://ghcr.io/bjw-s-labs/helm
```

Create `main/<project>/<app>/values.yaml` with **`app-template:` as the top-level key**:

```yaml
app-template:
  externalSecrets:
    <app>:
      refreshInterval: 5m
      secretStoreRef:
        kind: ClusterSecretStore
        name: onepassword-connect
      target:
        name: <app>-secret
        template:
          data:
            username: '{{ .username }}'
            password: '{{ .password }}'
      dataFrom:
        - extract:
            key: <1password-item-name>

  defaultPodOptions:
    securityContext:
      fsGroup: <gid>
      fsGroupChangePolicy: OnRootMismatch
      runAsGroup: <gid>
      runAsNonRoot: true
      runAsUser: <uid>
      seccompProfile:
        type: RuntimeDefault

  controllers:
    <app>:
      containers:
        app:
          image:
            repository: <image-repo>
            tag: <version>@sha256:<digest>
          env:
            TZ: America/Chicago
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            readOnlyRootFilesystem: true
          resources:
            requests:
              cpu: 10m
              memory: 128Mi
            limits:
              memory: 512Mi

  service:
    main:
      controller: <app>
      ports:
        http:
          port: &port 8080

  route:
    main:
      enabled: true
      parentRefs:
        - name: internal
          namespace: kube-system
          sectionName: https
      hostnames:
        - <app>.rsr.net
      rules:
        - matches:
            - path:
                type: PathPrefix
                value: /
          backendRefs:
            - name: <app>
              port: *port

  persistence:
    data:
      storageClass: longhorn
      accessMode: ReadWriteOnce
      size: 1Gi
      globalMounts:
        - path: /data
```

Notes:

- Inline `externalSecrets:` is the preferred pattern for app-template charts; `main/homelab/mosquitto/values.yaml` is the best reference.
- If you add a ConfigMap through `configMaps:`, the rendered ConfigMap name is the **release name** (`<app>`), not `<app>-config`. Mount it like this:

```yaml
app-template:
  configMaps:
    config:
      data:
        app.yaml: |
          setting: value

  persistence:
    config-file:
      type: configMap
      name: <app>
      globalMounts:
        - path: /config/app.yaml
          subPath: app.yaml
          readOnly: true
```

- If the app needs to avoid storage nodes, add this only when justified:

```yaml
app-template:
  defaultPodOptions:
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: storage
                  operator: DoesNotExist
```

- For apps that must run as a specific UID/GID, copy the style from a similar chart (`home-assistant`, `zwavejs2mqtt`, `teslamate`) and match the image's documented runtime user.
- Duplicate the `route.<name>` stanza with `parentRefs.name: public` when the app should also be internet-facing.

### Option B: plain-manifest chart

Use this when `app-template` is the wrong abstraction and you want raw manifests under `templates/`.

Create `main/<project>/<app>/Chart.yaml`:

```yaml
apiVersion: v2
name: <app>
description: <what this chart renders>
type: application
version: 0.1.0
appVersion: "<upstream-version>"
```

Then add raw manifests under `main/<project>/<app>/templates/`. Put the schema header on CRD-style resources and follow the same Envoy Gateway shape used elsewhere:

```yaml
---
# yaml-language-server: $schema=https://kube-schemas.pages.dev/gateway.networking.k8s.io/httproute_v1.json
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app>
spec:
  hostnames:
    - <app>.rsr.net
  parentRefs:
    - name: internal
      namespace: kube-system
      sectionName: https
  rules:
    - backendRefs:
        - name: <service-name>
          namespace: <namespace>
          port: 8080
```

Swap `internal` for `public` when the app belongs on the internet-facing Gateway instead.

If you need a standalone `ExternalSecret` template instead of inline `externalSecrets:`, escape the ExternalSecret template values so Helm does not try to evaluate them first:

```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <app>-secret
  namespace: <namespace>
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: <app>-secret
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        USERNAME: '{{ printf "{{ .username }}" }}'
        PASSWORD: '{{ printf "{{ .password }}" }}'
  dataFrom:
    - extract:
        key: <1password-item-name>
```

Important distinction:

- in **inline `app-template.externalSecrets` values**, current charts use `{{ .field_name }}` directly;
- in **raw files under `templates/`**, use `printf` escaping like the `home-assistant` secret template.

## 3. Register the app in the project's `applications:` list

Add an entry to `main/<project>/values.yaml`:

```yaml
applications:
  - name: <app>
    namespace: <namespace>
    path: main/<project>/<app>
    manifest-paths: /main/<project>/<app>
    sync-wave: "-1"
    helm:
      enabled: true
```

Guidance:

- `-1` is the common default for ordinary apps in `main/homelab/values.yaml`.
- If the app **depends on CRDs or an operator** created by another app, put the operator earlier and the consumer later (for example `-1` for the operator, `0` for the consuming app). Apps in the **same** ArgoCD sync wave have no guaranteed ordering.
- Add `syncOptions:` only when you actually need them (for example some monitoring apps use `RespectIgnoreDifferences=true`, `ServerSideApply=true`, or `Replace=true`).
- `helm.enabled: false` does **not** disable an app in this repo's generator; comment out or remove the whole entry if you want it gone.

## 4. Validate before you stop

Run at least:

```bash
helm template main/<project>/<app> -f main/<project>/<app>/values.yaml
pre-commit run --files \
  main/<project>/<app>/Chart.yaml \
  main/<project>/<app>/values.yaml \
  main/<project>/<app>/templates/*.yaml \
  main/<project>/values.yaml
```

Also check:

- the rendered chart contains the resources you expected (watch for the classic "only a ServiceAccount rendered" symptom);
- `HTTPRoute` parent refs point at the correct Gateway (`internal` or `public`) in `kube-system`;
- any `ServiceMonitor` you add has selectors/labels that actually match the target service and the monitoring stack's namespace selection.

## Common mistakes

- Using `<app>:` instead of **`app-template:`** as the top-level values key.
- Assuming a `configMaps.config` block creates `<app>-config`; in this repo's app-template usage it renders as **`<app>`**.
- Forgetting the `# yaml-language-server: $schema=...` header on raw CRD/Gateway manifests.
- Copying a `dataFrom.rewrite` prefixing trick from another repo; the current charts here normally use direct `dataFrom: [{ extract: { key: ... } }]` and name the 1Password fields appropriately.
- Forgetting Helm escaping in a standalone `templates/*secret*.yaml` ExternalSecret (`'{{ printf "{{ .field }}" }}'`).
- Splitting image version and digest into separate fields; this repo's convention is `tag: 1.2.3@sha256:...`.
- Hardcoding `runAsUser: 1001` or the `storage` anti-affinity on every app instead of checking whether the image and workload actually need them.
- Adding a `ServiceMonitor` whose labels/selectors do not match anything; ArgoCD will sync it fine, but Prometheus/VictoriaMetrics will silently never scrape it.
- Believing `helm.enabled: false` disables the Application; it does not in `main/templates/app.yaml`.
