# Handover — PageLM on GCP

Picking this up in Gemini (or any other tool). This file summarizes what's
already done and what's left, so you don't need to re-derive it from scratch.
The full spec is in [`pagelm-gcp-brief.md`](./pagelm-gcp-brief.md) — read that
first for the architecture, rationale, and acceptance criteria. This file is
just the status + next-steps layer on top of it.

## Repo state

- **origin**: https://github.com/Powerworks/pagelm-gcp (private) — this fork,
  with the GCP-specific changes below.
- **upstream**: https://github.com/CaviraOSS/PageLM — the original project,
  kept as a remote so future upstream changes can be pulled/merged.
- Working tree is clean as of this handover; latest commit is
  `3a13caf` "Adapt PageLM containers for Cloud Run compatibility" on `main`.

## Hard constraint: GCP account

**All GCP resources must be created under `william@hadisfarhealth.com`
(corporate account, for the free credits) — never under the personal
`williampower1@gmail.com` account.** Before running any `gcloud` command,
confirm `gcloud config get-value account` / active project is the corporate
one. If not yet authenticated:

```
gcloud auth login william@hadisfarhealth.com
gcloud config set account william@hadisfarhealth.com
```

A GCP **project ID** under that account has not been chosen/created yet —
that's the first thing to sort out (or confirm one already exists that should
be used).

## Phase 1 — Containerize: DONE

Completed and verified locally with `docker build` + `docker run` against
both Dockerfiles. Changes made (see commit `3a13caf`):

- `backend/Dockerfile` — `npm ci` → `npm install --legacy-peer-deps` (upstream
  lockfile had drifted out of sync with `package.json` — regenerated
  `package-lock.json` too); set `EXPOSE 8080`, `ENV PORT=8080`,
  `ENV HOST=0.0.0.0` as Cloud Run defaults.
- `frontend/Dockerfile` — `serve` was hardcoded to port 5173; changed the
  `CMD` to `serve -s dist -l tcp://0.0.0.0:${PORT}` so it honors Cloud Run's
  injected `$PORT`.
- `backend/src/config/env.ts` and `backend/src/core/index.ts` — both called
  `process.loadEnvFile('.env')` unconditionally, which **crashes the process
  on boot** if no `.env` file exists. On Cloud Run there is no mounted `.env`
  — config arrives via injected env vars / Secret Manager — so both call
  sites now check `fs.existsSync()` first and skip loading if absent.

**Verification done:** built both images locally, ran each with
`docker run -e PORT=8080 ...`, confirmed the backend boots and responds on
the injected port (needs a dummy `OPENAI_API_KEY` or similar to get past
module-load-time client construction in `backend/src/services/transcriber`,
even when `LLM_PROVIDER=ollama` — see "Known rough edges" below), and the
frontend serves and returns 200 on the injected port.

**Not yet done:** no actual Cloud Run deploy — everything above was validated
with local Docker only.

## Phase 2 — Storage wiring: NOT STARTED

Per the brief, PageLM's default persistence is flat JSON files on local disk
(`./storage` in dev, mounted via `docker-compose.yml`). This won't survive
Cloud Run's ephemeral containers as-is.

Steps:
1. Create a GCS bucket in the chosen project (single-user tool, so a small
   bucket in a nearby region is fine — pick based on where you are, cost is
   negligible either way).
2. Mount it into the **backend** Cloud Run service via Cloud Run's native GCS
   FUSE volume mount (`--add-volume` + `--add-volume-mount` on
   `gcloud run deploy`, or the equivalent `volumes`/`volumeMounts` block in a
   Cloud Run service YAML). Mount path should match wherever PageLM's
   storage code expects to write — check `backend/src/utils` and
   `backend/src/core` for the actual storage path (search for `./storage` or
   a `STORAGE_PATH`-style env var; none was found hardcoded as an env var in
   this pass, worth re-checking against current backend source before
   wiring the mount).
3. Confirm read/write actually works through the FUSE mount from inside a
   deployed revision — upload a doc, confirm a file lands in the bucket.
4. Separately, GCS is also needed for uploaded docs and generated podcast
   audio per the brief — decide whether that's the *same* bucket as the FUSE
   mount or a second one. Simplest: one bucket, FUSE-mounted, used for
   everything, since PageLM already treats storage as one flat filesystem
   tree.

## Phase 3 — Secrets and identity: NOT STARTED

- Create Secret Manager entries for whichever LLM provider key you're using
  (brief recommends Gemini via Vertex AI or AI Studio key — see
  `backend/src/config/env.ts` for the full list of supported provider env
  vars: `gemini`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `XAI_API_KEY`, etc.)
  and the TTS key if not using Google Cloud TTS via ADC.
- Create a dedicated Cloud Run service account (not the default compute SA)
  scoped to: read/write on just this project's bucket, and access to just
  this project's secrets. Least privilege, per the brief.
- Wire secrets into the Cloud Run service via `--set-secrets` at deploy time
  rather than baking them into env vars in a manifest.

## Phase 4 — Access control: NOT STARTED

**This is called out in the brief as the single most important step before
any public exposure** — PageLM has no built-in auth, so an unauthenticated
Cloud Run URL is a free LLM-relay for bots.

- Deploy both Cloud Run services **without** `--allow-unauthenticated`.
- Grant `roles/run.invoker` to `william@hadisfarhealth.com` only (or whichever
  identity you'll authenticate as day-to-day).
- Access pattern: either `gcloud run services proxy <service>` for CLI/local
  use, or front with Identity-Aware Proxy (IAP) if you want a normal browser
  flow with a Google sign-in prompt.
- **Before considering this phase done: actually test that an
  unauthenticated `curl` to the service URL gets rejected** (should be a 403
  from Cloud Run's IAM layer, not a 200 from the app).

## Phase 5 — Deploy and verify: NOT STARTED

- `gcloud run deploy` both services (frontend depends on knowing the
  backend's URL for `VITE_BACKEND_URL` build arg — the frontend Dockerfile
  takes this as a build-time `ARG`, so the backend needs to be deployed
  first, then the frontend image rebuilt/deployed pointing at the real
  backend Cloud Run URL).
- Confirm `min-instances=0` is set explicitly on both services (this is what
  actually delivers "normally off" — don't rely on the default).
- Set a GCS lifecycle rule to delete generated podcast audio after ~90 days.
- Set a GCP budget alert at €5–10/month.
- Let it sit idle for a day, then check the Cloud Run console shows zero
  instances for both services.
- Time a cold request from fully idle — brief's acceptance criterion is
  under ~30 seconds idle-to-usable.

## Known rough edges to keep in mind

- `backend/src/services/transcriber/index.ts` constructs an `OpenAI` client
  at **module import time**, which throws if no `OPENAI_API_KEY` is set —
  even when `LLM_PROVIDER` is set to something else (e.g. `ollama` or
  `gemini`). This didn't block Phase 1 since it was only hit during local
  smoke-testing with a dummy key, but it means **some `OPENAI_API_KEY` value
  will likely be required in the deployed env regardless of which LLM
  provider is actually configured**, unless this is fixed upstream or
  patched. Worth deciding whether to patch it (lazy-init the client) or just
  always provision an OpenAI key even if unused for the main LLM calls.
- Frontend Docker build takes `VITE_BACKEND_URL` as a **build arg**, baked
  into the static JS bundle at build time (Vite convention — `import.meta.env`
  vars are compile-time, not runtime). This means the frontend image must be
  rebuilt any time the backend's Cloud Run URL changes (e.g., first deploy
  before the URL is known, or if the backend service is ever recreated).
  Worth deciding whether that's acceptable for a personal tool (probably
  fine — it's a "build once per URL change" issue) or whether to switch to
  a runtime-config pattern (e.g., fetch a `/config.json` at app boot) if
  it becomes annoying.
- Local `npm install` on this machine used npm 10.9.8, while the Alpine base
  image (`node:22.16.0-alpine`) bundles npm 10.9.2. That version skew is why
  `npm ci` failed even right after a fresh `npm install` — different npm
  versions resolved slightly different optional/platform dependency sets
  into the lockfile. `npm install` in the Docker build sidesteps this but
  means the build isn't fully lockfile-reproducible. Not a problem for a
  personal deploy; flagging in case it causes confusion later.

## gcloud CLI gotchas hit this session

Worth knowing before running more `gcloud`/`gcloud builds submit` commands —
these cost real time to rediscover:

- **Shell is fish, not bash — bash heredocs (`<<EOF ... EOF`) don't work.**
  Piping a multiline string into a `gcloud` command (e.g. a YAML config) via
  a heredoc silently fails or hangs in fish with no useful error. Write the
  content to a temp file first (`Write`/`printf`), then pass `--file=path` or
  redirect from that file instead of trying to inline it.
- **Grant IAM roles upfront on a fresh project, don't wait for failures to
  reveal them.** A new project's default service accounts do *not* have the
  roles needed for a Cloud Build → Artifact Registry → Cloud Run pipeline.
  Grant these before the first build attempt (saves a full failed-build
  cycle each time one's missing):
  - Cloud Build SA (`$BUILD_SA`, `<PROJECT_NUMBER>@cloudbuild.gserviceaccount.com`):
    `roles/artifactregistry.writer`, `roles/iam.serviceAccountUser`,
    `roles/run.admin` (if Cloud Build itself deploys to Cloud Run).
  - Compute default SA (`$COMPUTE_SA`,
    `<PROJECT_NUMBER>-compute@developer.gserviceaccount.com`, used at Cloud
    Run runtime unless a dedicated SA is set up per Phase 3):
    `roles/storage.objectAdmin` (for the GCS FUSE mount in Phase 2), plus
    Secret Manager accessor once Phase 3's secrets exist.
- **Write a `.gcloudignore` before the first `gcloud builds submit`, or the
  upload hangs/fails.** Without one, Cloud Build tars up the entire working
  tree — including `.git`, `node_modules`, `dist` — which can be gigabytes
  and causes multi-minute uploads or timeouts. One now exists at repo root
  excluding `.git`, `.github`, `node_modules`, `dist`, `storage`.
- **Co-locate every resource in one region** — Artifact Registry repo, Cloud
  Build, GCS bucket(s), and both Cloud Run services should all use the same
  region to avoid cross-region latency and (for some resource pairs)
  outright errors. `europe-west1` (Belgium) or `europe-west2` (London) are
  reasonable defaults if no other constraint applies — pick one region and
  use it everywhere, don't let it default per-command.

## Quick reference

- Brief: [`pagelm-gcp-brief.md`](./pagelm-gcp-brief.md)
- Backend Dockerfile: `backend/Dockerfile` (build context is repo root)
- Frontend Dockerfile: `frontend/Dockerfile` (build context is `./frontend`)
- Local compose file (dev only, not used for Cloud Run): `docker-compose.yml`
- Env var reference: `.env.example` (placeholders only, no real values)
