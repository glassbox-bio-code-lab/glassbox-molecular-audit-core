# Customer Walkthrough: Pipeline Setup + Preflight UI

This guide is written as a screenshot-ready walkthrough for customer onboarding.

## 1. Prerequisites

1. Confirm required tools are installed:
```bash
kubectl version --client
helm version
node -v
npm -v
```
Screenshot placeholder: tool versions in terminal.

2. Confirm cluster access:
```bash
kubectl get ns
```
Screenshot placeholder: cluster namespace list.

3. Choose deployment profile (`starter`, `standard`, or `gpu`) and have the runner image/tag ready.
Screenshot placeholder: selected profile + image tag source.

## 2. Pipeline Setup (Customer Install + First Run)

### 2.0 Recommended one-command path (optional)

1. If you want the shortest, most repeatable setup path, run:
```bash
./github/examples/e2e-customer-pipeline.sh
```
Screenshot placeholder: e2e script output showing successful completion.

2. If you want manual control for screenshots and operator training, continue with steps 2.1 through 2.6 below.
Screenshot placeholder: transition note from script path to manual path.

### 2.1 Set run variables

1. Export the variables below from repo root (`marketplace_phase5_isolated`):
```bash
export APP_NAME="glassbox-mol-audit"
export NAMESPACE="glassbox-mol-audit"
export PROFILE_VALUES="github/manifest/chart/values-standard.yaml"
export IMAGE_REPO="us-central1-docker.pkg.dev/glassbox-marketplace-prod/glassbox-bio-molecular-audit/glassbox-mol-audit"
export IMAGE_TAG="1.0.0"
export PROJECT_ID="test"
export ENTITLEMENT_URL="https://glassbox-seal-662656813262.us-central1.run.app"
export RUN_ID="run_$(date -u +%Y%m%dT%H%M%SZ)"
```
Screenshot placeholder: exported variables (without secrets).

2. Create namespace once:
```bash
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
```
Screenshot placeholder: namespace apply output.

### 2.2 Install chart (phase 1: infra only)

1. Install with job disabled first (avoids immutable Job patch issues during iteration):
```bash
helm upgrade --install "$APP_NAME" github/manifest/chart \
  --namespace "$NAMESPACE" --create-namespace \
  -f "$PROFILE_VALUES" \
  --set job.enabled=false \
  --set image.repository="$IMAGE_REPO" \
  --set image.tag="$IMAGE_TAG" \
  --set config.projectId="$PROJECT_ID" \
  --set config.entitlementUrl="$ENTITLEMENT_URL" \
  --set config.runId="$RUN_ID"
```
Screenshot placeholder: successful Helm release output.

### 2.3 Stage inputs (PVC mode)

1. If using PVC storage, create a temporary writer pod mounted to the app PVC:
```bash
kubectl -n "$NAMESPACE" apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: gbx-input-writer
spec:
  restartPolicy: Never
  containers:
    - name: writer
      image: "$IMAGE_REPO:$IMAGE_TAG"
      command: ["bash","-lc"]
      args: ["sleep 3600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: "$APP_NAME-data"
YAML
kubectl -n "$NAMESPACE" wait --for=condition=Ready pod/gbx-input-writer --timeout=5m
```
Screenshot placeholder: writer pod ready.

2. Copy your customer input folder (`01_sources`) into the mounted path:
```bash
kubectl -n "$NAMESPACE" cp ./github/e2e/sample_input/test/01_sources "gbx-input-writer:/data/input/$PROJECT_ID"
```
Screenshot placeholder: `kubectl cp` success.

3. Verify required files exist:
```bash
kubectl -n "$NAMESPACE" exec gbx-input-writer -- bash -lc "ls -la /data/input/$PROJECT_ID/01_sources"
```
Screenshot placeholder: `01_sources` directory listing in pod.

4. Remove the temporary writer pod:
```bash
kubectl -n "$NAMESPACE" delete pod gbx-input-writer --ignore-not-found
```
Screenshot placeholder: writer pod deleted.

### 2.4 Start job (phase 2)

1. Enable job and run:
```bash
helm upgrade --install "$APP_NAME" github/manifest/chart \
  --namespace "$NAMESPACE" --create-namespace \
  -f "$PROFILE_VALUES" \
  --set job.enabled=true \
  --set image.repository="$IMAGE_REPO" \
  --set image.tag="$IMAGE_TAG" \
  --set config.projectId="$PROJECT_ID" \
  --set config.entitlementUrl="$ENTITLEMENT_URL" \
  --set config.runId="$RUN_ID"
```
Screenshot placeholder: Helm output for phase 2.

2. Watch job and logs:
```bash
kubectl -n "$NAMESPACE" get job "$APP_NAME" -w
kubectl -n "$NAMESPACE" logs "job/$APP_NAME" --all-containers --tail=200
```
Screenshot placeholder: running/completed job and logs.

### 2.5 Verify outputs and seal artifacts

1. Create a temporary output reader pod mounted to the same PVC:
```bash
kubectl -n "$NAMESPACE" apply -f - <<YAML
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
        claimName: "$APP_NAME-data"
YAML
kubectl -n "$NAMESPACE" wait --for=condition=Ready pod/gbx-output-reader --timeout=5m
```
Screenshot placeholder: output reader pod ready.

2. Confirm outputs exist:
```bash
kubectl -n "$NAMESPACE" exec gbx-output-reader -- /bin/sh -lc '
  find /data/output -maxdepth 5 -type f | sed -n "1,200p"
'
```
Screenshot placeholder: output artifact list.

3. Confirm seal artifacts (when online verification succeeds):
- `seal/seal.json`
- `seal/seal.sig` or `seal_sig` field in API response
- `seal/seal.svg`
- `seal/seal.png` (optional)
Screenshot placeholder: seal files in output path.

4. Remove the temporary output reader pod:
```bash
kubectl -n "$NAMESPACE" delete pod gbx-output-reader --ignore-not-found
```
Screenshot placeholder: output reader pod deleted.

### 2.6 Offline grace reconciliation (if run started offline)

1. After connectivity returns, replay the lifecycle with the same `run_id`:
- `consume`
- `run_start` (with `start_metadata_sha256`)
- `run_complete` (with `start_metadata_sha256`, `end_metadata_sha256`, `offline_grace_used=true`)

2. Validate reconciliation state from API response:
- `offline_grace.reconciled=true`
- `offline_grace.used_count` incremented once
Screenshot placeholder: run_complete response showing offline grace reconciliation.

## 3. Preflight UI Walkthrough (Operator Flow)

### 3.1 Start UI + backend locally

1. Start backend API (terminal A):
```bash
cd preflight
npm install
npm run server
```

2. Start frontend (terminal B):
```bash
cd preflight
npm run dev
```

3. Open:
- `http://localhost:3000`
Screenshot placeholder: landing page with `Preflight` and `Run + Logs` tabs.

### 3.2 Preflight tab

1. Stay on `Preflight` tab.
Screenshot placeholder: preflight tab selected.

2. Upload required files into slots:
- `sources.json`
- `targets.csv`
- `compounds.csv`
- `assays.csv`
Screenshot placeholder: all required slots attached.

3. Fill optional cloud context if used:
- `Input Bucket URI`
- `Output Bucket URI`
- `Project ID`
- `Config URI` (optional)
Screenshot placeholder: context fields populated.

4. Click `Run Preflight Check`.
Screenshot placeholder: processing animation / validation in progress.

5. Review Certification Report.
Screenshot placeholder: PASS/WARN/FAIL summary panel.

6. Click `Save Inputs to Cluster`.
Screenshot placeholder: success message with saved input path.

7. Click `Launch Glassbox Pipeline` (enabled after inputs are saved).
Screenshot placeholder: launch payload action completed.

### 3.3 Run + Logs tab

1. Switch to `Run + Logs`.
Screenshot placeholder: module hub visible.

2. Select module.
Screenshot placeholder: selected module card.

3. In `Run Controls`, set:
- `Namespace`
- `Project ID`
- Optional `Run ID`
- `Run Mode` (`Standard` or `Deep`)
- Optional `Enable GPU docking path`
Screenshot placeholder: completed Run Controls form.

4. Click `Start Run (billed)`.
Screenshot placeholder: status output showing job creation.

5. In `Pods`, choose pod and click `Stream Logs` (or use auto-stream).
Screenshot placeholder: pod selected + live logs moving.

6. In `Outputs`, use:
- `Refresh Outputs`
- `Download Repro Pack`
- quick links (`Safety Report`, `Unified Outputs`, `Seal` files)
Screenshot placeholder: outputs list and download buttons.

## 4. Screenshot Capture Checklist

1. Prereq tool versions.
2. Namespace creation.
3. Helm phase 1 success.
4. Input files staged in PVC.
5. Helm phase 2 success.
6. Job logs + completion.
7. Output artifacts + seal artifacts.
8. Offline grace reconciliation response (if applicable).
9. Preflight upload screen with required files.
10. Certification Report PASS/WARN/FAIL example.
11. Save Inputs to Cluster success.
12. Run + Logs job launch and live logs.
13. Outputs + Repro Pack download.
