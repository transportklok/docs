#!/usr/bin/env bash
# Rotate every secret named in incident-runbook.md, in kill-switch order.
# Usage: rotate-all.sh --dry-run | --execute
# --dry-run lists identifiers only. --execute runs rotators/<IDENTIFIER>.sh for each one
# (a missing rotator is reported and the run stops); it requires ROTATE_CONFIRM=yes.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Order matters: infrastructure, application, integrations, CI/CD, signing.
secrets=(
  AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY PRODUCTION_AWS_ROLE_ARN STAGING_AWS_ROLE_ARN
  DB_PASSWORD REDIS_PASSWORD MEMCACHED_PASSWORD
  BACKUP_ARCHIVE_PASSWORD MAIL_PASSWORD POSTMARK_TOKEN MAILGUN_SECRET APP_KEY
  NMBRS_CLIENT_SECRET NMBRS_SUBSCRIPTION_KEY LOKET_CLIENT_SECRET EXACT_ONLINE_CLIENT_SECRET
  AFAS_CLIENT_SECRET FLEETGO_CLIENT_SECRET WEBFLEET_CONNECT_API_KEY FLESPI_API_KEY
  TRACKMIJN_API_KEY CHARTMOGUL_API_KEY ABLY_KEY PUSHER_APP_KEY PUSHER_APP_SECRET MAPBOX_TOKEN
  COMPOSER_GITHUB_TOKEN CROSS_REPO_READ_TOKEN PLATFORM_CI_REPO_TOKEN GITLAB_TOKEN
  CAPAWESOME_TOKEN MOBILE_ENV_PRODUCTION GITHUB_TOKEN SENTRY_AUTH_TOKEN OPENAI_API_KEY
  TAURI_SIGNING_PRIVATE_KEY TAURI_SIGNING_PRIVATE_KEY_PASSWORD
  APPLE_CERTIFICATE APPLE_CERTIFICATE_PASSWORD APPLE_PASSWORD ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8
  IOS_DIST_P12_B64 IOS_DIST_P12_PASSWORD IOS_APPSTORE_PROFILE_B64
  ANDROID_KEYSTORE_B64 ANDROID_KEYSTORE_PASSWORD ANDROID_KEY_ALIAS ANDROID_KEY_PASSWORD
  PLAY_SERVICE_ACCOUNT_JSON
)

case "${1:-}" in
  --dry-run)
    for id in "${secrets[@]}"; do
      printf 'would rotate %s\n' "$id"
    done
    printf '%d secrets listed; nothing was changed.\n' "${#secrets[@]}"
    ;;
  --execute)
    [[ "${ROTATE_CONFIRM:-}" == "yes" ]] || { echo "set ROTATE_CONFIRM=yes to execute" >&2; exit 2; }
    for id in "${secrets[@]}"; do
      rotator="$here/rotators/$id.sh"
      [[ -x "$rotator" ]] || { echo "no rotator for $id; stopping" >&2; exit 1; }
      printf 'rotating %s\n' "$id"
      "$rotator"
    done
    ;;
  *)
    echo "usage: $0 --dry-run | --execute" >&2
    exit 2
    ;;
esac
