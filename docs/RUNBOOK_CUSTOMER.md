# Customer Runbook (CLI / Helm)

This runbook covers two roles:

- Customer: install and run the Kubernetes Job using Helm.
- Partner/admin: provision entitlements for the customer service account.

This mirrors the identity-only entitlement flow: the customer never receives or manages tokens. The Job authenticates to Cloud Run with Workload Identity.

## Prereqs (Customer)

- `kubectl` authenticated to your cluster.
- `helm` v3.
- A runner image accessible by the cluster.
- Storage:
  - PVC mode: a default StorageClass (or set `storage.pvc.storageClassName`)
  - GCS mode: GKE GCS Fuse CSI driver enabled
- Workload Identity configured for the Job service account.

## Prereqs (Partner/Admin)

- Access to call `POST /api/entitlement/issue` on the Entitlement + Seal API service.
- `X-GBX-ADMIN-TOKEN` (partner-only admin token).
- Ability to call the admin endpoint from an identity that can invoke the Cloud Run service.

## How Entitlements Work (Identity-Only)

The partner/admin provisions entitlements for the customer **service account principal** using:

- `POST /api/entitlement/issue`

The customer Job authenticates using Workload Identity and calls, per run, in order:

1. `POST /api/entitlement/check` with a unique `run_id`
2. `POST /api/entitlement/consume`
3. `POST /api/entitlement/run_start` with required metadata (`inputs_sha256`, `container_image`, `project_id`)
4. `POST /api/entitlement/run_complete` (returns the seal bundle)

## Customer: Step-by-Step (PVC Mode)

1. `cd` into the marketplace bundle root:

```bash
cd /path/to/glassbox-molecular-audit-core
```

2. Use a prebuilt runner image (provided by Glassbox or your internal registry).
   Set the image repo/tag in the next step.

3. Choose identifiers and the entitlement URL:

```bash
export APP_NAME="molecular-audit-core"
export NAMESPACE="molecular-audit-core"

export IMAGE_REPO="REGION-docker.pkg.dev/PROJECT/REPO/molecular-audit-core"
export IMAGE_TAG="latest"

export PROJECT_ID="test"  # used as /data/input/<PROJECT_ID> and for metadata
export RUN_ID="run_$(date +%Y%m%dT%H%M%SZ)"  # must be unique per run to avoid 409 reuse

export ENTITLEMENT_URL="https://YOUR_CLOUD_RUN_SERVICE"
export ENTITLEMENT_AUTH_MODE="google"
export ENTITLEMENT_AUDIENCE="${ENTITLEMENT_URL}"
export WORKLOAD_IDENTITY_GSA="your-sa@project.iam.gserviceaccount.com"
```

4. Create the namespace up front (recommended):

```bash
kubectl create namespace "${NAMESPACE}" 2>/dev/null || true
```

5. Install the chart (phase 1: infra only, job disabled):

```bash
helm upgrade --install "${APP_NAME}" ./manifest/chart \
  --namespace "${NAMESPACE}" --create-namespace \
  -f ./manifest/chart/values-standard.yaml \
  --set job.enabled=false \
  --set image.repository="${IMAGE_REPO}" \
  --set image.tag="${IMAGE_TAG}" \
  --set config.projectId="${PROJECT_ID}" \
  --set config.entitlementUrl="${ENTITLEMENT_URL}" \
  --set config.entitlementAuthMode="${ENTITLEMENT_AUTH_MODE}" \
  --set config.entitlementAudience="${ENTITLEMENT_AUDIENCE}" \
  --set workloadIdentity.enabled=true \
  --set workloadIdentity.gcpServiceAccount="${WORKLOAD_IDENTITY_GSA}" \
  --set config.runId="${RUN_ID}"
```

6. No entitlement Secret is required.

Entitlement is enforced using Workload Identity and the Cloud Run IAM policy. There are **no customer tokens**.

7. Stage inputs into the PVC at `/data/input/<PROJECT_ID>/01_sources/...`.

This example uses the sample bundle in this repo. Replace with your real inputs in production.

```bash
kubectl -n "${NAMESPACE}" delete pod gbx-input-writer --ignore-not-found
kubectl -n "${NAMESPACE}" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: gbx-input-writer
spec:
  restartPolicy: Never
  containers:
  - name: writer
    image: alpine:3.20
    command: ["/bin/sh","-lc"]
    args:
    - |
      set -euo pipefail
      mkdir -p "/data/input/${PROJECT_ID}"
      echo "ready"
      sleep 3600
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: ${APP_NAME}-data
YAML
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod/gbx-input-writer --timeout=5m
kubectl -n "${NAMESPACE}" cp "./e2e/sample_input/test/01_sources" "gbx-input-writer:/data/input/${PROJECT_ID}"
kubectl -n "${NAMESPACE}" exec gbx-input-writer -- /bin/sh -lc "chmod -R a+rwX /data/input/${PROJECT_ID} || true"
kubectl -n "${NAMESPACE}" exec gbx-input-writer -- /bin/sh -lc "ls -la /data/input/${PROJECT_ID}/01_sources | sed -n '1,200p'"
kubectl -n "${NAMESPACE}" delete pod gbx-input-writer --ignore-not-found
```

8. Enable the Job (phase 2: run). Jobs are immutable, so delete any previous Job first:

```bash
kubectl -n "${NAMESPACE}" delete job "${APP_NAME}" --ignore-not-found

helm upgrade --install "${APP_NAME}" ./manifest/chart \
  --namespace "${NAMESPACE}" \
  -f ./manifest/chart/values-standard.yaml \
  --set job.enabled=true \
  --set image.repository="${IMAGE_REPO}" \
  --set image.tag="${IMAGE_TAG}" \
  --set config.projectId="${PROJECT_ID}" \
  --set config.entitlementUrl="${ENTITLEMENT_URL}" \
  --set config.entitlementAuthMode="${ENTITLEMENT_AUTH_MODE}" \
  --set config.entitlementAudience="${ENTITLEMENT_AUDIENCE}" \
  --set workloadIdentity.enabled=true \
  --set workloadIdentity.gcpServiceAccount="${WORKLOAD_IDENTITY_GSA}" \
  --set config.runId="${RUN_ID}"
```

9. Watch the job:

```bash
kubectl -n "${NAMESPACE}" get job "${APP_NAME}" -o wide
kubectl -n "${NAMESPACE}" logs "job/${APP_NAME}" --all-containers --timestamps -f
```

10. Retrieve outputs.

Outputs are written under `config.outputPath/<run_id>` (default `/data/output/<RUN_ID>` when you set `config.runId`).

```bash
kubectl -n "${NAMESPACE}" delete pod gbx-output-reader --ignore-not-found
kubectl -n "${NAMESPACE}" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: gbx-output-reader
spec:
  restartPolicy: Never
  containers:
  - name: reader
    image: alpine:3.20
    command: ["/bin/sh","-lc"]
    args: ["sleep 3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: ${APP_NAME}-data
YAML
kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod/gbx-output-reader --timeout=5m
kubectl -n "${NAMESPACE}" exec gbx-output-reader -- /bin/sh -lc '
  ls -la /data/output
  find /data/output -maxdepth 5 \( -name run_manifest.json -o -path "*/seal/seal.json" -o -path "*/seal/seal.sig" -o -path "*/seal/seal.svg" \) -type f | sort | sed -n "1,200p"
'
kubectl -n "${NAMESPACE}" delete pod gbx-output-reader --ignore-not-found
```

## Customer: Workload Identity (Required)

Entitlements are identity-only. Always set:

- `config.entitlementAuthMode=google`
- `config.entitlementAudience=${ENTITLEMENT_URL}`
- `workloadIdentity.enabled=true`
- `workloadIdentity.gcpServiceAccount=your-sa@project.iam.gserviceaccount.com`

## Partner/Admin: Provision Entitlements

1. Set variables:

```bash
export ENTITLEMENT_URL="https://YOUR_CLOUD_RUN_SERVICE"
export GBX_ADMIN_TOKEN="PASTE_X_GBX_ADMIN_TOKEN"
```

2. Get an identity token for an account that can invoke Cloud Run:

```bash
export ID_TOKEN="$(gcloud auth print-identity-token --audiences="${ENTITLEMENT_URL}")"
```

3. Issue:

```bash
curl -sS -X POST "${ENTITLEMENT_URL}/api/entitlement/issue" \
  -H "Authorization: Bearer ${ID_TOKEN}" \
  -H "X-GBX-ADMIN-TOKEN: ${GBX_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "principal": "your-sa@project.iam.gserviceaccount.com",
    "plan_id": "gbx_standard",
    "runs_total": 5,
    "expires_at": "2026-12-31T00:00:00Z"
  }'
```

4. No customer secret is required. Entitlements are bound to the principal.

## Troubleshooting

### Helm install fails with Namespace ownership errors

Error like:
`Namespace "<name>" exists and cannot be imported ... meta.helm.sh/release-namespace must equal "default" ...`

Fix:

- Always pass `--namespace "${NAMESPACE}"` to Helm.
- Pre-create the namespace (or use Helm's `--create-namespace`) and ensure you're installing into the same namespace.

### Helm upgrade fails with Job immutable errors

Error like:
`cannot patch "<job>" with kind Job ... spec.template ... field is immutable`

Fix:

```bash
kubectl -n "${NAMESPACE}" delete job "${APP_NAME}" --ignore-not-found
```

Then re-run `helm upgrade`.

### PVC errors about size being less than capacity

Error like:
`spec.resources.requests.storage: Forbidden: field can not be less than status.capacity`

Fix:

- Do not shrink PVC size between installs. Stick to one profile, or increase the PVC size.
- If you must shrink, delete the PVC (data loss) and recreate.

### Entitlement API errors (from logs)

- `401/403`: identity token missing/invalid (Workload Identity or IAM invoker permission)
- `402`: entitlement exhausted
- `409`: `run_id` reuse / already consumed (use a new `RUN_ID`)
- `422`: missing prerequisites (must call `consume` then `run_start` before `run_complete`)

## Technical Diagram

Open `github/docs/E2E_RUN_LIFECYCLE_DIAGRAM.html` for a visual sequence diagram of the full lifecycle (issue → deploy → consume → run_start → run_complete → seal).
