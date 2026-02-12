# Image Build Notes

This repo is the Marketplace distribution bundle (chart + schema + deployer).
Container images are expected to be built and pushed separately.

## Deployer image

The deployer image is used by Marketplace Click-to-Deploy tooling.

Build/push:

```bash
make deployer-build \
  REGION=us-central1 \
  PROJECT_ID=YOUR_PROJECT \
  REPO=YOUR_REPO \
  SERVICE_NAME=services/YOUR_SERVICE_NAME \
  TRACK=1.0 \
  VERSION=1.0.0
```

## Runner / Console images

The Helm chart references:

- `image.repository` / `image.tag`: the audit runner image.
- `console.image.repository` / `console.image.tag`: optional in-cluster console.

Ensure the images exist in the registry location you provide in your values.

### Runner image (customer job)

Build and push the runner image (tags both `latest` and a unique timestamp tag):

```bash
cd github
make runner-build-push \
  REGION=us-central1 \
  PROJECT_ID=YOUR_PROJECT \
  REPO=YOUR_REPO \
  SERVICE_NAME=services/YOUR_SERVICE_NAME
```

Optional: pin a specific tag for reproducibility:

```bash
make runner-build-push \
  REGION=us-central1 \
  PROJECT_ID=YOUR_PROJECT \
  REPO=YOUR_REPO \
  RUNNER_TAG=dev-20260207-01 \
  SERVICE_NAME=services/YOUR_SERVICE_NAME
```

Notes:
- Runner builds use `docker compose` with `docker-compose.cvp.local.yml` in the bundle root.
- The compose build outputs a local image named `glassbox-mol-audit:latest`, which is then tagged/pushed to Artifact Registry.
- `runner-build-push` also builds/pushes the Marketplace aux images (`ubbagent` and the Verification-only `tester`) by default. Set `GBX_PUSH_AUX_IMAGES=0` to skip.
