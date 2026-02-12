#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="molecular-audit-core"
APP_NAME="molecular-audit-core"
IMAGE_REPO="REGION-docker.pkg.dev/PROJECT/REPO/molecular-audit-core"
IMAGE_TAG="1.0.0"

helm upgrade --install "${APP_NAME}" ./manifest/chart \
  --namespace "${NAMESPACE}" --create-namespace \
  -f ./manifest/chart/values-standard.yaml \
  --set image.repository="${IMAGE_REPO}" \
  --set image.tag="${IMAGE_TAG}" \
  --set config.projectId="mol_audit_demo"
