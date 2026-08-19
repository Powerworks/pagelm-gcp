# PageLM on GCP — Project Brief

**Owner:** William
**Purpose:** self-hosted study tool (PageLM — open-source NotebookLM alternative) for exam prep (AZ104 and others) and general book/paper study. Hand this to Claude Code or Gemini as the build spec.

## 1. Goal

Stand up CaviraOSS/PageLM on GCP such that it costs effectively nothing while idle and is ready within seconds to a couple of minutes when needed. This is a personal study tool, not a hosted service — optimise for zero standing cost over responsiveness.

## 2. The core constraint: normally off

Everything in this brief is driven by one requirement — no component should bill while unused. That rules out anything with a persistent instance (Compute Engine VM, Cloud SQL, a GKE node pool) as the primary architecture. Serverless-only:

- **Cloud Run** for both frontend and backend — scales to zero automatically when there's no traffic. No manual start/stop needed; this is Cloud Run's default behaviour, not something to build.
- **Firestore** (or Cloud Storage) for the app's data store — genuinely pay-per-use, no idle charge.
- **Cloud Storage** for uploaded documents and generated podcast audio.

Accept a cold-start delay (roughly 5–15 seconds on first request after idle) as the trade-off for zero idle cost. That's a fine trade for a study tool you open a few times a week.

## 3. Architecture

```
Browser (William, authenticated via Google identity)
        │
        ▼
Cloud Run — frontend (React/Vite, served as static build via nginx)
        │
        ▼
Cloud Run — backend (Node/TypeScript, LangChain)
        │
        ├── Firestore or GCS — JSON data store (PageLM's default persistence)
        ├── Cloud Storage — uploaded docs (PDF/DOCX/MD) + generated podcast audio
        ├── Secret Manager — LLM API key(s), TTS key(s)
        └── LLM provider — Gemini (Vertex AI or AI Studio API), matches existing GCP-native tooling
```

**Persistence detail worth getting right:** PageLM's default storage is flat JSON files on local disk, which doesn't survive Cloud Run's ephemeral, scale-to-zero containers as-is. Mount a Cloud Storage bucket into the container via **Cloud Run's GCS FUSE volume mount** — this makes the bucket appear as a normal filesystem path to the app, so PageLM's file-based storage works unmodified rather than requiring a code change to point it at Firestore.

## 4. Access control — do this before making it public

PageLM ships no authentication of its own. An unauthenticated Cloud Run URL is discoverable and will eventually get bot traffic, and every request that reaches an LLM call is money. Do not deploy with `--allow-unauthenticated`.

- Deploy Cloud Run with authentication **required**.
- Grant the Cloud Run Invoker IAM role to your own Google identity only.
- Access it either via `gcloud run services proxy` for CLI-side use, or front it with **Identity-Aware Proxy (IAP)** if you want normal browser access with a Google sign-in prompt.

This is the single most important thing to get right before the first deploy — skipping it turns a free personal tool into an exposed LLM API relay.

## 5. Model and TTS provider choice

- **LLM:** Gemini via Vertex AI or an AI Studio API key. Keeps everything inside GCP billing, avoids spinning up a separate provider relationship for a low-usage personal tool. PageLM supports Ollama too, so if the home-lab GPU situation changes later, local inference is a drop-in swap, not a re-architecture.
- **TTS (for the AI Podcast feature):** Google Cloud TTS — same reasoning, one bill, one IAM boundary, no separate ElevenLabs key to manage for occasional use.

## 6. Cost guardrails

- GCP budget alert at a low threshold (e.g. €5–10/month) — this should almost never trigger given the usage pattern, so treat any alert as a signal something's misconfigured (stuck in a loop, or `min-instances` accidentally set above 0).
- Confirm `min-instances=0` explicitly on both Cloud Run services — this is what actually delivers "normally off."
- Set a Cloud Storage lifecycle rule to delete generated podcast audio after, say, 90 days, since it's disposable output, not source material worth retaining indefinitely.

## 7. Build phases

1. **Containerise** — confirm PageLM's existing `docker-compose.prod.yml` split (frontend on nginx, backend on Node) translates cleanly to two Cloud Run services; adjust Dockerfiles if needed for Cloud Run's port/health-check expectations.
2. **Storage wiring** — set up the Cloud Storage bucket, GCS FUSE mount for the backend service, and confirm PageLM's file-based storage writes/reads correctly through the mount.
3. **Secrets and identity** — Secret Manager entries for the Gemini key and TTS key; Cloud Run service account with least-privilege access to just its own bucket and secrets.
4. **Access control** — authenticated-only Cloud Run, IAM invoker binding, IAP if browser access is wanted. Test that an unauthenticated request is actually rejected before considering this done.
5. **Deploy and verify cold start** — confirm the idle-to-ready latency is acceptable, confirm `min-instances=0` holds (check the Cloud Run console after a day of no traffic — should show zero instances).

## 8. Acceptance criteria

- No component bills anything during a week of non-use, beyond a few cents of storage.
- An unauthenticated request to the Cloud Run URL is rejected.
- Uploading a document, generating flashcards/quiz/notes, and generating a podcast all work end-to-end through the GCS-mounted storage.
- Cold start from fully idle to usable is under ~30 seconds.
