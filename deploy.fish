#!/usr/bin/env fish

set -g REGION "europe-west1"
set -g PROJECT_ID (gcloud config get-value project)
# Using modern Artifact Registry path
set -g FRONTEND_IMAGE "$REGION-docker.pkg.dev/$PROJECT_ID/pagelm-repo/pagelm-frontend:latest"

# 1. Fetch Backend Cloud Run URL dynamically
echo "🔍 Fetching backend Cloud Run URL..."
set -g BACKEND_URL (gcloud run services describe pagelm-backend --region=$REGION --format='value(status.url)' 2>/dev/null)

if test -z "$BACKEND_URL"
  echo "⚠️ Backend service 'pagelm-backend' not found, defaulting to empty or local."
  set -g BACKEND_URL ""
else
  echo "✅ Found backend URL: $BACKEND_URL"
end

# 2. Submit build with VITE_API_URL build argument
echo "📦 Submitting multi-stage container build to Cloud Build..."
echo "steps:
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '--build-arg', 'VITE_API_URL=$BACKEND_URL', '-t', '$FRONTEND_IMAGE', '-f', 'frontend/Dockerfile', '.']
images: ['$FRONTEND_IMAGE']" > cloudbuild.yaml

gcloud builds submit --config=cloudbuild.yaml .
and rm cloudbuild.yaml
and echo "☁️ Deploying container to Cloud Run..."
and gcloud run deploy pagelm-frontend \
  --image=$FRONTEND_IMAGE \
  --region=$REGION \
  --allow-unauthenticated \
  --port=80

or begin
  echo "❌ Build or deploy failed. Stopping pipeline."
  rm -f cloudbuild.yaml
  exit 1
end

# 3. Get live Frontend URL
set -x FRONTEND_URL (gcloud run services describe pagelm-frontend --region=$REGION --format='value(status.url)')
echo "🎉 Frontend live at: $FRONTEND_URL"

# 4. Automatically update the backend Cloud Run service with the new frontend URL for CORS
echo "🔗 Wiring Frontend URL to Backend Cloud Run service for CORS..."
gcloud run services update pagelm-backend \
  --region=$REGION \
  --update-env-vars FRONTEND_URL=$FRONTEND_URL

echo "✨ Full pipeline deployment and CORS sync complete!"
