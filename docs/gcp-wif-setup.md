# GCP Workload Identity Federation Setup

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
gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:github-deploy@${PROJECT_ID}.iam.gserviceaccount.com" --role="roles/compute.admin"
```

## 3. Create Workload Identity Pool and OIDC Provider

```bash
gcloud iam workload-identity-pools create github-pool --location=global --display-name="GitHub Actions Pool"
gcloud iam workload-identity-pools providers create-oidc github-provider --location=global --workload-identity-pool=github-pool --display-name="GitHub Provider" --attribute-mapping=google.subject=assertion.sub,attribute.repository=assertion.repository --attribute-condition="assertion.repository == 'OWNER/REPO'" --issuer-uri=https://token.actions.githubusercontent.com
```

## 4. Allow GitHub to impersonate the service account

```bash
gcloud iam service-accounts add-iam-policy-binding github-deploy@${PROJECT_ID}.iam.gserviceaccount.com --role=roles/iam.workloadIdentityUser --member="principalSet://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/attribute.repository/OWNER/REPO"
```

## 5. Set GitHub secrets and variables

```bash
gh secret set GCP_WORKLOAD_IDENTITY_PROVIDER --body "projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/github-pool/providers/github-provider"
gh secret set GCP_SERVICE_ACCOUNT --body "github-deploy@${PROJECT_ID}.iam.gserviceaccount.com"
gh variable set GCP_PROJECT --body "$PROJECT_ID"
```
