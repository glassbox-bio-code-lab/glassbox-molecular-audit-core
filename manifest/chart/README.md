# Glassbox Bio Molecular Audit Helm Chart

Helm chart for running the Glassbox Bio Molecular Audit job on Kubernetes.

## Install

```bash
helm upgrade --install molecular-audit-core ./manifest/chart \
  --namespace molecular-audit-core --create-namespace \
  -f ./manifest/chart/values-standard.yaml \
  --set image.repository=REGION-docker.pkg.dev/PROJECT/REPO/molecular-audit-core \
  --set image.tag=1.0.0 \
  --set config.projectId=mol_audit_demo
```

## Deployment profiles (supported)

We officially support three opinionated deployment profiles to reduce support
surface area:

| Profile               | Expected runtime range | Rough cost range | Required cluster resources                      | When to use it                                                      |
| --------------------- | ---------------------- | ---------------- | ----------------------------------------------- | ------------------------------------------------------------------- |
| Starter (CPU)         | 1–4h (cap 4h)          | $$               | 1–2 vCPU, 4–8Gi RAM, 20Gi PVC                   | Fast validation runs, smallest datasets, cost-sensitive trials      |
| Standard (CPU)        | 2–6h (cap 6h)          | $$$              | 2–4 vCPU, 8–16Gi RAM, 50Gi PVC                  | Default choice for most audits; balanced speed vs cost              |
| Deep / GPU (optional) | 4–8h (cap 8h)          | $$$$             | 4–8 vCPU, 32–64Gi RAM, 1x NVIDIA GPU, 200Gi PVC | Deep evidence expansion, docking-heavy or GPU-accelerated workflows |

```bash
helm upgrade --install molecular-audit-core ./manifest/chart \
  -f ./manifest/chart/values-starter.yaml
```

```bash
helm upgrade --install molecular-audit-core ./manifest/chart \
  -f ./manifest/chart/values-standard.yaml
```

```bash
helm upgrade --install molecular-audit-core ./manifest/chart \
  -f ./manifest/chart/values-gpu.yaml
```

## Storage options

PVC (default):

```bash
helm upgrade --install molecular-audit-core ./manifest/chart \
  --set storage.type=pvc \
  --set storage.pvc.storageClassName=standard \
  --set storage.pvc.size=50Gi
```

GCS Fuse (GKE):

```bash
helm upgrade --install molecular-audit-core ./manifest/chart \
  --set storage.type=gcs \
  --set storage.gcs.bucket=YOUR_BUCKET \
  --set workloadIdentity.enabled=true \
  --set workloadIdentity.gcpServiceAccount=your-sa@project.iam.gserviceaccount.com
```

## Entitlement + Seal API (Cloud Run)

The runner calls the Glassbox Entitlement + Seal API to:

- enforce per-run entitlements
- track run metadata (hashes, image id, project id)
- issue a signed seal bundle at run completion

### Configure the API URL

```bash
helm upgrade --install molecular-audit-core ./manifest/chart \
  --set config.entitlementUrl="https://YOUR_CLOUD_RUN_SERVICE"
```

### OIDC caller auth (recommended)

The entitlement service uses the caller's OIDC identity token (`Authorization: Bearer ...`) as the principal.
To have the runner attach an identity token automatically:

```bash
helm upgrade --install molecular-audit-core ./manifest/chart \
  --set config.entitlementUrl="https://YOUR_CLOUD_RUN_SERVICE" \
  --set config.entitlementAuthMode="auto" \
  --set config.entitlementAudience="https://YOUR_CLOUD_RUN_SERVICE"
```

Notes:

- If Cloud Run is IAM-protected, requests can be rejected at the edge with `403` before reaching the app.
  For Marketplace/customer clusters, prefer allowing invocation and enforcing auth inside the app via OIDC verification.

### Local/dev principal pinning (no OIDC)

For local testing against a non-google-mode entitlement service, you can pin a principal:

```bash
helm upgrade --install molecular-audit-core ./manifest/chart \
  --set config.entitlementUrl="http://localhost:8081" \
  --set config.entitlementAuthMode="principal" \
  --set config.entitlementPrincipal="local-dev"
```

Common failure modes:

- `401/403`: identity token missing/invalid (OIDC auth) or Cloud Run edge IAM blocking invocation
- `402`: entitlement exhausted
- `409`: `run_id` reuse / already consumed
- `422`: missing prerequisite state (e.g. `run_start` not recorded)

## Outputs

Outputs are written under `/data/output` inside the container and on the mounted
volume or bucket:

- `results/summary.json`
- `results/metrics.json`
- `results/phase5_combined_report.html`
- `results/phase5_comprehensive_report.html`
- `results/phase5_unified_report.html`
- `seal/` (seal.json, seal.sig, seal.svg, VERIFY.md)

Notes:

- By default the runner generates a unique `run_id` and writes to `OUTPUT_PATH/<run_id>`.
- If you set `config.runId`, the chart sets `GBX_RUN_ID=<runId>` so outputs land under `OUTPUT_PATH/<runId>`.
