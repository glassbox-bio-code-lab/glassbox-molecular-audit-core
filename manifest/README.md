# Marketplace Deployment Bundle

This folder contains the Kubernetes configuration used to deploy Glassbox Bio
Molecular Audit.

## Contents

- `chart/` - Helm chart used by Marketplace and CLI installs.
- `application.yaml` - Application custom resource template (envsubst).
- `manifests.yaml` - Placeholder for Click-to-Deploy structure parity.

## Supported deployment profiles

We support three opinionated deployment profiles. Choose exactly one:

| Profile | Expected runtime range | Rough cost range | Required cluster resources | When to use it |
| --- | --- | --- | --- | --- |
| Starter (CPU) | 1–4h (cap 4h) | $$ | 1–2 vCPU, 4–8Gi RAM, 20Gi PVC | Fast validation runs, smallest datasets, cost-sensitive trials |
| Standard (CPU) | 2–6h (cap 6h) | $$$ | 2–4 vCPU, 8–16Gi RAM, 50Gi PVC | Default choice for most audits; balanced speed vs cost |
| Deep / GPU (optional) | 4–8h (cap 8h) | $$$$ | 4–8 vCPU, 32–64Gi RAM, 1x NVIDIA GPU, 200Gi PVC | Deep evidence expansion, docking-heavy or GPU-accelerated workflows |

Values files:

- `manifest/chart/values-starter.yaml`
- `manifest/chart/values-standard.yaml`
- `manifest/chart/values-gpu.yaml`

## How Marketplace uses this bundle

Marketplace deploys the Helm chart using `schema.yaml` to collect user inputs
and supply them as Helm values. The Application resource is applied alongside
the chart so that users can manage the app as a single unit.
