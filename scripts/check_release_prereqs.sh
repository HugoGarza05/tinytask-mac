#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_SLUG="${1:-}"

exit_code=0

print_ok() {
  printf "OK   %s\n" "$1"
}

print_warn() {
  printf "MISS %s\n" "$1"
  exit_code=1
}

check_command() {
  local command_name="$1"
  local label="$2"

  if command -v "${command_name}" >/dev/null 2>&1; then
    print_ok "${label}"
  else
    print_warn "${label}"
  fi
}

check_env() {
  local variable_name="$1"
  local label="$2"

  if [[ -n "${(P)variable_name:-}" ]]; then
    print_ok "${label}"
  else
    print_warn "${label}"
  fi
}

echo "TinyTaskMac stable release prerequisite check"
echo "Project: ${ROOT_DIR}"
echo

check_command xcodebuild "Full Xcode available"
check_command xcrun "xcrun available"
check_command codesign "codesign available"
check_command xcodegen "xcodegen available"
check_command gh "GitHub CLI available"

echo
check_env CODESIGN_IDENTITY "CODESIGN_IDENTITY is set"
check_env NOTARYTOOL_KEYCHAIN_PROFILE "NOTARYTOOL_KEYCHAIN_PROFILE is set"

if [[ -n "${CODESIGN_IDENTITY:-}" ]] && command -v security >/dev/null 2>&1; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -F "${CODESIGN_IDENTITY}" >/dev/null 2>&1; then
    print_ok "Developer ID identity is present in the local keychain"
  else
    print_warn "Developer ID identity is not present in the local keychain"
  fi
fi

echo

if [[ -n "${REPO_SLUG}" ]]; then
  if gh auth status >/dev/null 2>&1; then
    print_ok "GitHub CLI is authenticated"

    secret_names="$(gh secret list -R "${REPO_SLUG}" 2>/dev/null | awk '{print $1}')"

    for secret_name in \
      NETLIFY_AUTH_TOKEN \
      NETLIFY_SITE_ID \
      TINYTASKMAC_CODESIGN_IDENTITY \
      TINYTASKMAC_DEVELOPER_ID_CERT_BASE64 \
      TINYTASKMAC_DEVELOPER_ID_CERT_PASSWORD \
      TINYTASKMAC_KEYCHAIN_PASSWORD \
      TINYTASKMAC_NOTARY_KEY_ID \
      TINYTASKMAC_NOTARY_ISSUER_ID \
      TINYTASKMAC_NOTARY_PRIVATE_KEY
    do
      if print -r -- "${secret_names}" | grep -Fx "${secret_name}" >/dev/null 2>&1; then
        print_ok "GitHub secret ${secret_name} exists in ${REPO_SLUG}"
      else
        print_warn "GitHub secret ${secret_name} is missing in ${REPO_SLUG}"
      fi
    done
  else
    print_warn "GitHub CLI is not authenticated"
  fi
else
  echo "GitHub secret check skipped. Pass a repo slug, for example:"
  echo "  ./scripts/check_release_prereqs.sh HugoGarza05/tinytask-mac"
fi

echo

if [[ "${exit_code}" -eq 0 ]]; then
  echo "Stable release prerequisites look complete."
else
  echo "Stable release prerequisites are incomplete."
fi

exit "${exit_code}"
