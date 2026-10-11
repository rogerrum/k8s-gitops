# Repository Guidelines

## Universal AI Contributor Rules
These instructions are tool-agnostic and apply to any coding assistant (Codex, Copilot, Claude, etc.).

- Make minimal, focused changes; avoid unrelated refactors.
- Prefer editing existing files over creating new patterns.
- Explain assumptions before risky changes (secrets, infra behavior, destructive ops).
- Never commit plaintext secrets, tokens, or kube credentials.
- Before staging/committing, check `git status` for untracked files that
  shouldn't be swept in (private keys, `.DS_Store`, local reference
  checkouts) — never `git add -A`/`git add .` blindly.
- Validate changes locally with the commands in this file before proposing merge.

## Project Structure & Module Organization
This is an ArgoCD App-of-Apps GitOps repo for a k3s homelab cluster. Nodes run
their existing OS (not Talos). Applications are plain Helm charts (most
depending on the `app-template` chart from `oci://ghcr.io/bjw-s-labs/helm`,
pinned to `5.2.1`), registered via a custom `applications:` list in each
project's `values.yaml` (e.g. `main/homelab/values.yaml`, `main/ai/values.yaml`),
which a shared Helm template (`templates/app.yaml`) expands into ArgoCD
`Application` resources. **No Kustomize** anywhere in this repo — plain Helm
only.

- `apps/`: root app that bootstraps ArgoCD-managed applications (`apps/values.yaml` registers the top-level `argocd`, `infrastructure`, `main`, `root`, `system-upgrade` Applications).
- `argocd/`: ArgoCD's own chart/values.
- `infrastructure/`: shared cluster services (networking, storage, certs, operators) — e.g. `cilium`/`cilium-bgp`, `envoy-gateway`, `longhorn`, `external-secrets`, `cert-manager`, `kyverno`, `kopia`/`volsync`, `dragonfly-operator`.
- `main/`: workload apps as sibling "projects", each its own `Chart.yaml` + `values.yaml` + `templates/` (same generator pattern as `apps/`), each registered in `main/values.yaml`:
  - `homelab/`: general self-hosted apps (default namespace).
  - `ai/`: AI/LLM stack (`ai` namespace) — litellm-operator, litellm, context7-mcp; see `main/ai/STEPS.md`.
  - `logs/`, `monitoring/`: logging and observability stacks (own namespaces).
- `setup/`: bootstrap/maintenance scripts (cluster bootstrap, Vault, password/hash generators).
- `system-upgrade/`: Rancher system-upgrade-controller manifests.
- `docs/` and `mkdocs.yaml`: documentation and publish config.
- `.agents/skills/`: reusable task playbooks for coding agents (e.g. `add-app`),
  discoverable via the `.claude/skills` symlink.

### Renovate / Forgejo hosting convention
Day-to-day pushes, PRs, and Renovate runs happen against the **internal,
self-hosted Forgejo** instance (`git.rsr.net`, LAN/Tailscale-only — not
internet-exposed). Renovate itself runs in-cluster as a `RenovateJob` CR via
the `renovate-operator` (`main/homelab/renovate-operator/`), not as a GitHub
Actions workflow or hosted GitHub App; its own config lives in `renovate.json5`.
Forgejo push-mirrors `main` to GitHub after merges, so **GitHub remains the
ArgoCD source of truth and the disaster-recovery copy** (ArgoCD's `repo.url`
stays pointed at GitHub intentionally — it's outside the cluster, so it still
works if the cluster, and therefore Forgejo, is down). Treat GitHub as
read-only by convention (don't push feature branches / open PRs there
directly) but do **not** lock it with hard branch-protection — keep
emergency push access for cluster rebuild scenarios.

### AI PR review
`.forgejo/workflows/pr-reviewer.yaml` runs an AI-assisted PR review on each
PR. It routes entirely to a local, self-hosted Ollama server
(`192.168.1.16:11434`) via the in-cluster `litellm` proxy (`main/ai/`) — no
cloud LLM provider or API billing is involved. A Context7 MCP tool
(`main/ai/context7-mcp/`) is registered at the proxy layer for live docs
lookups during review. See `main/ai/STEPS.md` for the setup/model details
and manual one-time steps (Forgejo Authorized Integration, 1Password items).

## Architecture
- **Cluster**: k3s, 3 control-plane nodes + a mix of amd64 worker/storage
  nodes and a couple of arm/arm64 Pi workers. A cluster-wide Kyverno
  mutating policy (`infrastructure/kyverno/templates/prefer-worker-nodes-policy.yaml`)
  soft-prefers scheduling pods onto workers over control-plane nodes.
  Nodes labeled `storage=enabled` (the dedicated Longhorn storage nodes) can
  suffer I/O contention; latency-sensitive apps add an explicit hard
  anti-affinity to avoid them:
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
- **Ingress**: Envoy Gateway with `HTTPRoute`/`Gateway` (NOT Traefik or
  `Ingress`). Two `Gateway`s in `kube-system`: `internal`
  (`192.168.100.151`, `*.rsr.net`, LAN/Tailscale) and `public`
  (`192.168.100.152`, `*.techbuzzworld.com`, internet-facing via Cloudflare).
  Forgejo's SSH listener (port 22) shares the `internal` gateway's IP.
- **LB IPAM**: Cilium BGP (`infrastructure/cilium-bgp`) — **not** MetalLB,
  even though some charts still carry a redundant
  `metallb.universe.tf/...` annotation alongside the real
  `lbipam.cilium.io/ips` one.
- **Storage**: Longhorn (default StorageClass) for in-cluster PVCs. Backups
  go through **VolSync** (`infrastructure/volsync`), backed by a **Kopia**
  repository (`infrastructure/kopia`, `kube-system`, `sync-wave: "-3"`) —
  this is the active backup path. A separate `kopiur` operator (a
  different, CRD-driven Kopia backup controller) was trialed and rolled
  back after repeated indefinite/stalled backups; its chart/config is kept
  in git but fully commented out in `infrastructure/values.yaml` (not
  merely `helm.enabled: false` — see the Standards note below on why that
  alone isn't enough to disable an app).
- **Secrets**: `ExternalSecret` CRDs only (no plaintext), sourced from a
  1Password Connect `ClusterSecretStore` named `onepassword-connect`. No
  HashiCorp Vault in this repo despite `setup/bootstrap-vault.sh`'s name —
  that script manages 1Password-backed bootstrap secrets.
- **Sync**: ArgoCD with `selfHeal: true` on most apps — any committed
  `values.yaml` drift from the live Helm release (including an accidental
  downgrade) gets auto-applied on the next sync. A webhook HTTPRoute
  (`infrastructure/argocd-patch/templates/webhook-httproute.yaml`) lets
  Forgejo push events trigger near-immediate ArgoCD sync instead of waiting
  out the default poll interval.
- **CI**: Forgejo Actions workflows in `.forgejo/workflows/`:
  `diff-hr-on-pr.yaml` (Helm Release Differ, posts a rendered-manifest diff
  comment on PRs touching chart YAML), `labeler.yaml`, and
  `pr-reviewer.yaml` (AI review, see above). Renovate auto-bumps
  images/charts per `renovate.json5`; there is no separate AI-gated review
  step for Renovate PRs beyond the same `pr-reviewer.yaml`.
- **Monitoring**: `main/monitoring/` (own namespace) — VictoriaMetrics-based
  stack, `grafana-operator`/`silence-operator` for Grafana + Alertmanager
  silences. Apps expose metrics via `ServiceMonitor` CRs
  (`monitoring.coreos.com/v1`); labels/namespace selectors must line up or
  the target silently never gets scraped.

## Scaffolding a New App
See `.agents/skills/add-app/SKILL.md` (discoverable via the `.claude/skills`
symlink) for the full playbook: chart layout (`app-template` vs
plain-manifest), `values.yaml` conventions, `applications:` list
registration/sync-wave ordering, and validation steps, with concrete
snippets pulled from real charts in this repo.

## Secrets & Credential Generation
- `ExternalSecret`s here pull **all fields of one 1Password item** via
  `dataFrom: [{extract: {key: "<Item Name>"}}]` and reference them directly
  as `{{ .field_name }}` in `target.template.data` — field names must
  already match what's stored in 1Password (no `rewrite`/prefixing trick is
  used in this repo). Multiple apps commonly share one 1Password item
  (e.g. `postgres-config`, `emqx-config`) when their credentials are
  related. See `main/homelab/home-assistant/templates/home-assistant-secret.yaml`
  and `main/homelab/mosquitto/values.yaml` for reference.
- In a **standalone** `templates/*-secret.yaml` ExternalSecret (as opposed
  to `app-template`'s inline `externalSecrets:` key), escape the ESO
  template so Helm doesn't try to evaluate it first:
  `'{{ printf "{{ .field_name }}" }}'`.
- No `op`/`mosquitto_passwd`/vendor CLI tooling is assumed available
  locally — bespoke password/hash generators live in `setup/` (e.g.
  `setup/generate-mosquitto-password.sh`) when a credential needs a
  non-trivial hash format before it can be stored in 1Password.
- Force an `ExternalSecret` to re-pull from 1Password immediately (don't
  wait out `refreshInterval`):
  ```bash
  kubectl annotate externalsecret <name> force-sync=$(date +%s) --overwrite
  ```

## Troubleshooting
- **ArgoCD `selfHeal` downgrade risk**: before removing/loosening an
  explicit `image:`/`tag:` override to "match upstream defaults", confirm
  the chart's bundled default isn't actually older than what's currently
  running (`kubectl get pod <pod> -o jsonpath='{.spec.containers[*].image}'`)
  — `selfHeal: true` will silently apply a downgrade on the next sync
  otherwise.

## Build, Test, and Development Commands
- `pre-commit install`: install local hooks.
- `pre-commit run --all-files`: run whitespace/line-ending/smart-quote/secret checks.
- `helm template <chart-dir> -f <chart-dir>/values.yaml`: render manifests for validation.
  - Example: `helm template main/monitoring -f main/monitoring/values.yaml`
- `cd setup && ./bootstrap-cluster.sh`: one-time cluster/app bootstrap.
- `cd setup && ./bootstrap-objects.sh`: apply envsubst-driven object updates.
- `cd setup && ./bootstrap-vault.sh`: apply 1Password-backed bootstrap secret updates.

## Standards
- **Images**: pin `tag@sha256:<digest>` together in the same `tag:` field
  (not a separate `digest:` field) — see any `app-template` chart's
  `containers.app.image` for the pattern.
- **Security**: non-root preferred (check image docs for required UID,
  commonly `1001`), read-only rootfs where the app supports it, drop
  capabilities by default.
- **Naming**: kebab-case for all chart directories and Kubernetes resources.
- **Schemas**: include a `yaml-language-server: $schema=...` comment on the
  first line of CRD manifests (ExternalSecret, HTTPRoute, Gateway,
  provider-specific CRs, etc.) for in-editor validation.
- **No Kustomize**: intentionally avoided throughout — plain Helm charts only.
- **Disabling an app**: setting `helm.enabled: false` on an `applications:`
  entry does **not** stop ArgoCD from managing it (`templates/app.yaml`
  never reads that field) — the whole entry must be commented out to
  actually remove the Application.

## Coding Style & Naming Conventions
- YAML uses 2-space indentation; no tabs; use LF line endings.
- Keep chart changes scoped: values and templates stay inside their chart directory.
- Use clear, component-aligned names for Kubernetes resources.
- Follow existing directory naming conventions (`kebab-case` chart folders).

## Testing Guidelines
- No unit-test suite is defined; validation is Helm render + policy/lint checks.
- Run `pre-commit run --all-files` before opening a PR.
- Render every changed chart with `helm template` before merge.
- For `Chart.yaml`/`values.yaml` updates, review CI Helm Release Differ output on the PR.

## Commit & Pull Request Guidelines
- Use Conventional Commit style used in history: `feat(scope): ...`, `fix(scope): ...`.
- Keep commits atomic (one chart/component per commit when practical).
- PR description should include:
  - changed paths,
  - operational impact (if any),
  - manual rollout or follow-up steps.
