#!/usr/bin/env bash
set -euo pipefail

# End-to-end "customer" pipeline for the Marketplace bundle.
# Requires: kubectl auth to a cluster, helm v3.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
CHART_DIR="${GITHUB_ROOT}/manifest/chart"

APP_NAME="${APP_NAME:-molecular-audit-core}"
NAMESPACE="${NAMESPACE:-molecular-audit-core}"
PROFILE_VALUES="${PROFILE_VALUES:-${CHART_DIR}/values-starter.yaml}" # or values-standard.yaml / values-gpu.yaml

IMAGE_REPO="${IMAGE_REPO:-us-central1-docker.pkg.dev/glassbox-marketplace-prod/glassbox-bio-molecular-audit/molecular-audit-core}"
IMAGE_TAG="${IMAGE_TAG:-1.0.0}"
PROJECT_ID="${PROJECT_ID:-test}"
ENTITLEMENT_URL="${ENTITLEMENT_URL:-https://glassbox-seal-662656813262.us-central1.run.app}"

# Optional: deterministic run_id (also controls output subdir name).
RUN_ID="${RUN_ID:-}"

# Optional: private Cloud Run IAM auth (Workload Identity identity token).
ENTITLEMENT_AUTH_MODE="${ENTITLEMENT_AUTH_MODE:-}"   # e.g. "google"
ENTITLEMENT_AUDIENCE="${ENTITLEMENT_AUDIENCE:-}"     # usually same as ENTITLEMENT_URL
WORKLOAD_IDENTITY_ENABLED="${WORKLOAD_IDENTITY_ENABLED:-0}" # set 1 to enable
WORKLOAD_IDENTITY_GSA="${WORKLOAD_IDENTITY_GSA:-}"   # your-sa@project.iam.gserviceaccount.com

CONSOLE_ENABLED="${CONSOLE_ENABLED:-false}"

# Use the on-disk sample input bundle by default.
SAMPLE_INPUT_DIR="${SAMPLE_INPUT_DIR:-${GITHUB_ROOT}/e2e/sample_input/test}"

# If set to 1, create the entitlement secret required by the runner container.
# These values are product-specific; leave unset unless you have the right values.
CREATE_ENTITLEMENT_SECRET="${CREATE_ENTITLEMENT_SECRET:-0}"
ENTITLEMENT_TOKEN="${ENTITLEMENT_TOKEN:-}"
OFFLINE_GRACE_TOKEN="${OFFLINE_GRACE_TOKEN:-}"
ENTITLEMENT_PUBLIC_KEY_B64="${ENTITLEMENT_PUBLIC_KEY_B64:-}"
SEAL_PUBLIC_KEY_B64="${SEAL_PUBLIC_KEY_B64:-}"

SECRET_NAME="${SECRET_NAME:-${APP_NAME}-entitlement}"
PVC_NAME="${PVC_NAME:-${APP_NAME}-data}"

echo "[e2e] namespace=${NAMESPACE} app=${APP_NAME} image=${IMAGE_REPO}:${IMAGE_TAG}"
echo "[e2e] NOTE: identity-only entitlements: the runner authenticates with Workload Identity (Authorization bearer token)."
echo "[e2e] NOTE: ENTITLEMENT_TOKEN/OFFLINE_GRACE_TOKEN are not required for entitlement enforcement."

HELM_AUTH_ARGS=()
if [[ -n "${RUN_ID}" ]]; then
  HELM_AUTH_ARGS+=(--set "config.runId=${RUN_ID}")
fi
if [[ -n "${ENTITLEMENT_AUTH_MODE}" ]]; then
  HELM_AUTH_ARGS+=(--set "config.entitlementAuthMode=${ENTITLEMENT_AUTH_MODE}")
fi
if [[ -n "${ENTITLEMENT_AUDIENCE}" ]]; then
  HELM_AUTH_ARGS+=(--set "config.entitlementAudience=${ENTITLEMENT_AUDIENCE}")
fi
if [[ "${WORKLOAD_IDENTITY_ENABLED}" == "1" ]]; then
  HELM_AUTH_ARGS+=(--set "workloadIdentity.enabled=true")
  if [[ -n "${WORKLOAD_IDENTITY_GSA}" ]]; then
    HELM_AUTH_ARGS+=(--set "workloadIdentity.gcpServiceAccount=${WORKLOAD_IDENTITY_GSA}")
  fi
fi

echo "[e2e] installing chart (phase 1: create infra, job disabled)"
helm upgrade --install "${APP_NAME}" "${CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  -f "${PROFILE_VALUES}" \
  --set job.enabled=false \
  --set console.enabled="${CONSOLE_ENABLED}" \
  --set image.repository="${IMAGE_REPO}" \
  --set image.tag="${IMAGE_TAG}" \
  --set config.projectId="${PROJECT_ID}" \
  --set config.entitlementUrl="${ENTITLEMENT_URL}" \
  "${HELM_AUTH_ARGS[@]}"

if [[ -n "${CLONE_ENTITLEMENT_SECRET_FROM_NS:-}" && -n "${CLONE_ENTITLEMENT_SECRET_NAME:-}" ]]; then
  echo "[e2e] cloning entitlement secret from ${CLONE_ENTITLEMENT_SECRET_FROM_NS}/${CLONE_ENTITLEMENT_SECRET_NAME} -> ${NAMESPACE}/${SECRET_NAME}"
  kubectl -n "${CLONE_ENTITLEMENT_SECRET_FROM_NS}" get secret "${CLONE_ENTITLEMENT_SECRET_NAME}" -o yaml \
    | sed "s/^  name: ${CLONE_ENTITLEMENT_SECRET_NAME}$/  name: ${SECRET_NAME}/" \
    | sed "s/^  namespace: ${CLONE_ENTITLEMENT_SECRET_FROM_NS}$/  namespace: ${NAMESPACE}/" \
    | kubectl -n "${NAMESPACE}" apply -f - >/dev/null
fi

if [[ "${CREATE_ENTITLEMENT_SECRET}" == "1" ]]; then
  echo "[e2e] creating entitlement secret ${SECRET_NAME}"
  kubectl -n "${NAMESPACE}" delete secret "${SECRET_NAME}" --ignore-not-found
  kubectl -n "${NAMESPACE}" create secret generic "${SECRET_NAME}" \
    --from-literal=entitlement_token="${ENTITLEMENT_TOKEN}" \
    --from-literal=offline_grace_token="${OFFLINE_GRACE_TOKEN}" \
    --from-literal=entitlement_public_key_b64="${ENTITLEMENT_PUBLIC_KEY_B64}" \
    --from-literal=seal_public_key_b64="${SEAL_PUBLIC_KEY_B64}"
else
  echo "[e2e] NOTE: not creating entitlement secret (${SECRET_NAME}). This is expected for identity-only entitlements."
fi

echo "[e2e] waiting for pvc ${PVC_NAME} (if using pvc storage)"
kubectl -n "${NAMESPACE}" get pvc "${PVC_NAME}" >/dev/null 2>&1 && \
  kubectl -n "${NAMESPACE}" wait --for=jsonpath='{.status.phase}'=Bound "pvc/${PVC_NAME}" --timeout=5m || true

echo "[e2e] staging sample inputs into ${PVC_NAME} (PVC mode only)"
if kubectl -n "${NAMESPACE}" get pvc "${PVC_NAME}" >/dev/null 2>&1; then
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
      # Avoid external images (docker.io) in Marketplace environments. Reuse the runner image.
      image: "${IMAGE_REPO}:${IMAGE_TAG}"
      imagePullPolicy: IfNotPresent
      securityContext:
        runAsUser: 0
      command: ["bash","-lc"]
      args:
        - |
          set -euo pipefail
          mkdir -p "/data/input/${PROJECT_ID}"
          echo "[e2e] writer pod ready for kubectl cp into /data/input/${PROJECT_ID}"
          sleep 3600
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: "${PVC_NAME}"
YAML
  kubectl -n "${NAMESPACE}" wait --for=condition=Ready pod/gbx-input-writer --timeout=5m

  if [[ ! -d "${SAMPLE_INPUT_DIR}/01_sources" ]]; then
    echo "[e2e] ERROR: sample input dir not found: ${SAMPLE_INPUT_DIR}/01_sources"
    exit 1
  fi

  echo "[e2e] copying ${SAMPLE_INPUT_DIR}/01_sources -> pvc:/data/input/${PROJECT_ID}/"
  kubectl -n "${NAMESPACE}" cp "${SAMPLE_INPUT_DIR}/01_sources" "gbx-input-writer:/data/input/${PROJECT_ID}"
  # The job container runs as a non-root user; ensure the project dir is writable for staging artifacts.
  kubectl -n "${NAMESPACE}" exec gbx-input-writer -- bash -lc "chmod -R a+rwX /data/input/${PROJECT_ID} || true"
  echo "[e2e] verifying inputs exist in pvc"
  kubectl -n "${NAMESPACE}" exec gbx-input-writer -- bash -lc "ls -la /data/input/${PROJECT_ID}/01_sources && test -f /data/input/${PROJECT_ID}/01_sources/sources.json"

  kubectl -n "${NAMESPACE}" delete pod gbx-input-writer --ignore-not-found
fi

echo "[e2e] installing chart (phase 2: enable job)"
helm upgrade --install "${APP_NAME}" "${CHART_DIR}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  -f "${PROFILE_VALUES}" \
  --set job.enabled=true \
  --set console.enabled="${CONSOLE_ENABLED}" \
  --set image.repository="${IMAGE_REPO}" \
  --set image.tag="${IMAGE_TAG}" \
  --set config.projectId="${PROJECT_ID}" \
  --set config.entitlementUrl="${ENTITLEMENT_URL}" \
  "${HELM_AUTH_ARGS[@]}"

echo "[e2e] job status"
kubectl -n "${NAMESPACE}" get job "${APP_NAME}" -o wide || true
kubectl -n "${NAMESPACE}" describe job "${APP_NAME}" | sed -n '1,120p' || true

echo "[e2e] streaming job logs (best-effort)"
kubectl -n "${NAMESPACE}" logs "job/${APP_NAME}" --all-containers --timestamps --tail=200 || true

echo "[e2e] waiting for job completion (or failure)"
deadline=$(( $(date +%s) + 8*60*60 ))
while true; do
  if kubectl -n "${NAMESPACE}" get job "${APP_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}' 2>/dev/null | grep -q True; then
    break
  fi
  if kubectl -n "${NAMESPACE}" get job "${APP_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Failed")].status}' 2>/dev/null | grep -q True; then
    echo "[e2e] job failed"
    kubectl -n "${NAMESPACE}" logs "job/${APP_NAME}" --all-containers --timestamps --tail=500 || true
    exit 1
  fi
  if [[ "$(date +%s)" -ge "${deadline}" ]]; then
    echo "[e2e] timeout waiting for job"
    kubectl -n "${NAMESPACE}" get job "${APP_NAME}" -o wide || true
    exit 1
  fi
  sleep 10
done

echo "[e2e] final job logs"
kubectl -n "${NAMESPACE}" logs "job/${APP_NAME}" --all-containers --timestamps --tail=500

echo "[e2e] done"
