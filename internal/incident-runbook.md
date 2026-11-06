# Incident runbook: suspected breach

Goal: a suspected breach is made harmless within **60 minutes**. This page names every secret by identifier only. Never paste a secret value into chat, a ticket, a PR or this file.
Unpublished: `internal/` is listed in `.mintignore`.

## 1. Who decides (minute 0 to 5)

- **Incident lead**: Redmar Bakker (fallback: the Release Management owner). The lead alone declares the incident and orders the kill switch.
- Anyone who suspects a breach pages the lead directly (phone first, then chat). Do not wait for proof; wrong alarms are cheap, late alarms are not.
- Lead writes the start time in the incident log (section 3) and names a scribe.

## 2. Kill-switch order (minute 5 to 35)

Stop the attacker's access first, then rotate. Do each step, note the time, move on. Production changes go only through the protected GitHub Actions workflow and the AWS console/CLI; Terraform is never run from a terminal.

1. **Cut the entry point**: block the suspect IP/path at the load balancer or WAF; disable the exposed endpoint or upload route.
2. **Revoke sessions and tokens**: invalidate all user sessions and Sanctum tokens (`SANCTUM_TOKEN_PREFIX` family); sign out mobile clients.
3. **Rotate infrastructure credentials** (blast radius largest first):
   - AWS: `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`; role ARNs `PRODUCTION_AWS_ROLE_ARN`, `STAGING_AWS_ROLE_ARN` (review the trust policy, deactivate stale sessions).
   - Secrets Manager entries: platform production (`production_secret_name` in `platform/terraform/PROD`), `transportklok/staging/platform`, TrackMijn `<name>/runtime` (PROD and STAGING).
   - Databases and caches: `DB_PASSWORD`, `REDIS_PASSWORD`, `MEMCACHED_PASSWORD`.
4. **Rotate application secrets**: `APP_KEY` (last: it logs everyone out and invalidates encrypted data, plan re-encryption first), `BACKUP_ARCHIVE_PASSWORD`, `MAIL_PASSWORD`, `POSTMARK_TOKEN`, `MAILGUN_SECRET`.
5. **Rotate integration secrets**: `NMBRS_CLIENT_SECRET`, `NMBRS_SUBSCRIPTION_KEY`, `LOKET_CLIENT_SECRET`, `EXACT_ONLINE_CLIENT_SECRET`, `AFAS_CLIENT_SECRET`, `FLEETGO_CLIENT_SECRET`, `WEBFLEET_CONNECT_API_KEY`, `FLESPI_API_KEY`, `TRACKMIJN_API_KEY`, `CHARTMOGUL_API_KEY`, `ABLY_KEY`, `PUSHER_APP_KEY`, `PUSHER_APP_SECRET`, `MAPBOX_TOKEN`.
6. **Rotate CI/CD secrets** (GitHub Actions): `COMPOSER_GITHUB_TOKEN`, `CROSS_REPO_READ_TOKEN`, `PLATFORM_CI_REPO_TOKEN`, `GITLAB_TOKEN`, `CAPAWESOME_TOKEN`, `MOBILE_ENV_PRODUCTION`, and the workspace `GITHUB_TOKEN`; also `SENTRY_AUTH_TOKEN`, `OPENAI_API_KEY`.
7. **Rotate signing material last, only if the build chain is suspected**: `TAURI_SIGNING_PRIVATE_KEY` (+ `_PASSWORD`), Apple (`APPLE_CERTIFICATE`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_PASSWORD`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `IOS_DIST_P12_B64`, `IOS_DIST_P12_PASSWORD`, `IOS_APPSTORE_PROFILE_B64`), Android (`ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `PLAY_SERVICE_ACCOUNT_JSON`), `APPLICATION_BUNDLES_TRUSTED_SIGNING_KEY_IDS`.
8. **Redeploy** staging then production via the GitHub Actions deploy workflow so running tasks pick up the new values; confirm health.
9. **Verify harmless**: old credentials are rejected, new ones work, no unknown sessions, no unknown IAM users or keys.

`internal/rotate-all.sh` follows this order: run `internal/rotate-all.sh --dry-run` first to list every secret identifier it would rotate.

**Still to do:** the secret list above is drawn from workflow secrets and config names and is not yet checked against the real Secrets Manager contents.

## 3. Evidence capture (starts at minute 0, in parallel)

Capture before anything is rotated or redeployed; rotation must not destroy evidence.

- Snapshot affected hosts/containers and the database (RDS snapshot); keep read-only.
- Export web, application, WAF, CloudTrail and Sentry logs for the window from 7 days before first suspicion.
- Record: first indicator, affected systems, actions taken with UTC timestamps, who did them.
- Store in the restricted incident folder; never in the repo or in chat.

## 4. Notification (minute 35 to 60 and after)

- **Internal**: all engineering and support within the hour.
- **Customers**: the lead decides, in Dutch, factual, no secret values.
- **Autoriteit Persoonsgegevens**: if personal data is involved, report within **72 hours** of becoming aware (AVG art. 33); affected individuals when the risk is high (art. 34).
- Post-incident: blameless review within 5 working days; update this runbook.

## 5. Rehearsal

Rehearse once on staging (dry-run of the rotate-all script, then the real staging rotation) and record the elapsed time against the 60-minute goal. Not yet rehearsed.
