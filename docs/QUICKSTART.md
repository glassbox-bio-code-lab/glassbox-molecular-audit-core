CAN: Perfect. I’ll draft this as a **Google Cloud Marketplace–ready Quickstart document**, structured exactly how reviewers expect it, and incorporating your link cleanly and professionally.

You can paste this into the Marketplace “Documentation” section as your Quickstart page.

---

# Quickstart — Glassbox Bio Target Diligence Core

Glassbox Bio Target Diligence Core deploys as a Kubernetes workload within your Google Cloud environment. All audit computation and data processing occur inside your project.

---

## Prerequisites

Before deployment, ensure the following:

* A Google Cloud project with billing enabled
* A running GKE cluster (Standard or Autopilot)
* IAM permissions to deploy Marketplace applications
* Helm (v3+) and kubectl installed (for CLI deployment option)
* Optional: GPU-enabled node pool for Deep profile runs

---

## Option 1 — Deploy via Google Cloud Marketplace (Recommended)

1. Navigate to the product listing:
   [https://console.cloud.google.com/marketplace/product/glassbox-bio/molecular-audit-core](https://console.cloud.google.com/marketplace/product/glassbox-bio/molecular-audit-core)

2. Click **Deploy**

3. Select:

   * Target GKE cluster
   * Namespace
   * Storage configuration (PVC or GCS bucket)

4. Review the pricing summary (usage-based billing, 1 unit per run)

5. Click **Deploy**

The Marketplace interface handles container image wiring and entitlement configuration automatically.

---

## Option 2 — Deploy via Helm (Advanced)

For customers managing deployments via infrastructure-as-code:

```bash
helm upgrade --install molecular-audit-core ./manifest/chart \
  --namespace molecular-audit-core --create-namespace \
  -f ./manifest/chart/values-standard.yaml \
  -f ./examples/values-gcs.yaml \
  --set storage.gcs.bucket=YOUR_BUCKET \
  --set workloadIdentity.gcpServiceAccount=your-sa@project.iam.gserviceaccount.com \
  --set config.projectId=YOUR_PROJECT_ID
```

---

## Verify Installation

After deployment:

```bash
kubectl get pods -n molecular-audit-core
```

Expected components:

* molecular-audit-core (audit workload)
* console (optional UI component)
* billing agent (Marketplace metering sidecar)

---

## Run Your First Audit

1. Upload input files (structure, sequence, or configuration)
2. Launch an audit job via console or CLI
3. Monitor logs in Cloud Logging
4. Download output artifacts
5. Verify the cryptographic provenance seal (if issued)

---

## Billing Model

* Usage-based billing through Google Cloud Marketplace
* 1 billing unit is reported at run start
* No subscription or idle charges
* Usage metering handled automatically via Service Control

---

## Data Boundary & Security

* Customer data remains within the customer’s GCP project
* Images are pulled from Google Artifact Registry
* Entitlement calls transmit metadata only (run ID and hashes)
* No external telemetry or model API calls

---

## Formatting & Input Requirements

For detailed information on supported input formats, configuration options, and validation requirements:

**For more information on correct formatting/inputs, visit:**
[https://www.glassbox-bio.com/docs/quickstart](https://www.glassbox-bio.com/docs/quickstart)

---

This structure is:

✔ Marketplace-reviewer friendly
✔ Enterprise clear
✔ Not overly verbose
✔ Properly separates deployment from deeper docs
✔ Reinforces data isolation

If you want, I can now tighten this further to exactly match Google’s Marketplace documentation formatting expectations (they do have specific tone preferences).
