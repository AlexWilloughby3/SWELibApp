# GCP Workload Identity Federation Setup

Deploys SWELibApp to a GCE VM via GitHub Actions using keyless authentication (WIF). The Lean-compiled deploy binary validates VM state transitions against the formal SWELib spec, then SSHes into the VM to deploy Docker containers (PostgreSQL + backend API) using SWELib's typed `DockerRunConfig`.

## Prerequisites

- GCP project with Compute Engine API enabled
- `gcloud` CLI installed and on PATH
- `gh` CLI installed and authenticated
- Replace `OWNER/REPO` with your GitHub repo (e.g. `AlexWilloughby3/SWELibApp`)

## 1. Authenticate and set project

```bash
gcloud auth login
export PROJECT_ID="your-gcp-project"
gcloud config set project $PROJECT_ID
export PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
```

## 2. Create service account

```bash
gcloud iam service-accounts create github-deploy --display-name="GitHub Actions Deploy"
```

Grant it Compute Engine admin and service account user roles:

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:github-deploy@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/compute.admin"
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:github-deploy@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/iam.serviceAccountUser"
```

## 3. Create Workload Identity Pool and OIDC Provider

```bash
gcloud iam workload-identity-pools create github-pool --location=global --display-name="GitHub Actions Pool"
gcloud iam workload-identity-pools providers create-oidc github-provider --location=global --workload-identity-pool=github-pool --display-name="GitHub Provider" --attribute-mapping=google.subject=assertion.sub,attribute.repository=assertion.repository --attribute-condition="assertion.repository == 'OWNER/REPO'" --issuer-uri=https://token.actions.githubusercontent.com
```

The `--attribute-condition` is required by GCP and restricts which GitHub repos can authenticate through this pool.

## 4. Allow GitHub to impersonate the service account

```bash
gcloud iam service-accounts add-iam-policy-binding github-deploy@${PROJECT_ID}.iam.gserviceaccount.com --role=roles/iam.workloadIdentityUser --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/OWNER/REPO"
```

## 5. Set GitHub secrets and variables

```bash
# GCP authentication
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
gh secret set GCP_SERVICE_ACCOUNT --body "github-deploy@${PROJECT_ID}.iam.gserviceaccount.com"
gh variable set GCP_PROJECT --body "$PROJECT_ID"

# Container configuration
gh secret set PG_PASSWORD      # prompted for value — the PostgreSQL password
gh secret set JWT_SECRET       # prompted for value — JWT signing secret
gh variable set BACKEND_IMAGE --body "gcr.io/${PROJECT_ID}/prodtracker-api:latest"
```

## How the GitHub Action works

Defined in `.github/workflows/deploy.yml`. Triggers on push to `main` or manual dispatch.

**Job 1 — `build`**: Checks out both `SWELibApp` and `SWELib`, installs the Lean toolchain (elan) and system libraries (libssl, libpq, libcurl, libssh2), compiles the deploy binary with `lake build deploy`, and uploads it as an artifact.

**Job 2 — `deploy`**: Downloads the binary, authenticates to GCP via WIF (GitHub OIDC token exchanged for short-lived GCP credentials), sets up `gcloud`, then runs `./deploy deploy`. The Lean binary:

1. Checks for an existing VM, validates the state transition against the formal spec, and creates/starts the VM via `gcloud compute instances` commands
2. SSHes into the VM via `gcloud compute ssh` and runs a provisioning script that installs Docker, pulls images, and starts two containers:
   - **prodtracker-db** — PostgreSQL 16 (Alpine) with a persistent `pg-data` volume
   - **prodtracker-api** — Backend server connecting to postgres at `localhost:5432`

Both containers use `--network host` and `--restart unless-stopped`.

## Deploy commands

The binary supports multiple subcommands:

| Command | Description |
|---------|-------------|
| `deploy deploy` | Create/start VM and deploy containers (runs on push to `main`) |
| `deploy containers` | Redeploy containers on a running VM without recreating it |
| `deploy supervise` | Poll container health every 30s, restart failures |
| `deploy status` | Show current VM state |
| `deploy stop` | Stop the VM |
| `deploy delete` | Stop and delete the VM |

## Triggering a deploy manually

**Via `gh` CLI:**

```bash
gh workflow run deploy.yml --repo AlexWilloughby3/SWELibApp
```

**Via REST API:**

```bash
curl -X POST \
  -H "Authorization: Bearer $(gh auth token)" \
  -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/AlexWilloughby3/SWELibApp/actions/workflows/deploy.yml/dispatches \
  -d '{"ref": "main"}'
```

**Watch a run:**

```bash
gh run list --repo AlexWilloughby3/SWELibApp --workflow deploy.yml
gh run watch --repo AlexWilloughby3/SWELibApp
```

## Troubleshooting

- **"Invalid value for audience"**: The `GCP_WORKLOAD_IDENTITY_PROVIDER` secret must use the numeric project number, not the project ID string. Verify with: `gcloud iam workload-identity-pools providers describe github-provider --location=global --workload-identity-pool=github-pool --format="value(name)"`
- **"Permission 'iam.serviceAccounts.getAccessToken' denied"**: The service account needs `roles/iam.serviceAccountUser` (step 2) and the WIF binding (step 4). Verify with: `gcloud iam service-accounts get-iam-policy github-deploy@${PROJECT_ID}.iam.gserviceaccount.com`
- **"attribute condition must reference one of the provider's claims"**: GCP requires `--attribute-condition` on OIDC providers. See step 3.
