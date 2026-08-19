#!/usr/bin/env fish

echo "📦 Submitting container to Cloud Build..."
echo "steps:
- name: 'gcr.io/cloud-builders/docker'
  args: ['build', '-t', '$FRONTEND_IMAGE', '-f', 'frontend/Dockerfile', '.']
images: ['$FRONTEND_IMAGE']" > cloudbuild.yaml

gcloud builds submit --config=cloudbuild.yaml .
and rm cloudbuild.yaml
and echo "☁️ Deploying to Cloud Run..."
and gcloud run deploy pagelm-frontend \
  --image=$FRONTEND_IMAGE \
  --region=$REGION \
  --allow-unauthenticated \
  --port=80

or begin
  echo "❌ Build or deploy failed. Stopping."
  rm -f cloudbuild.yaml
  exit 1
end

set -x FRONTEND_URL (gcloud run services describe pagelm-frontend --region=$REGION --format='value(status.url)')
echo "🎉 Frontend is live at: $FRONTEND_URL"
