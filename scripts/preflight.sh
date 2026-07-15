#!/usr/bin/env bash
# Repository hygiene gate. Run before every push; also intended as a CI job.
#
# Checks that nothing secret-like or explicitly denied is tracked, staged,
# or present in file contents / commit history. Repo-specific deny patterns
# can be added locally in .git/info/preflight-deny (path regexes, one per
# line) and .git/info/preflight-deny-content (content regexes); those files
# are not tracked, so local policy stays local.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail=0

# --- 1. Path deny-list -------------------------------------------------------
deny='(^|/)\.env(\..+)?$|\.tfstate|\.tfvars$|(^|/)tfplan$|\.tfplan$|\.pem$|\.key$|\.p12$|\.pfx$|(^|/)id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$'
if [ -f .git/info/preflight-deny ]; then
  while IFS= read -r extra; do
    [ -n "$extra" ] && deny="$deny|$extra"
  done < .git/info/preflight-deny
fi

echo "[1/5] Tracked and staged paths vs deny-list"
hits=$({ git ls-files; git diff --cached --name-only; } | sort -u | grep -E "$deny")
if [ -n "$hits" ]; then echo "$hits" | sed 's/^/  DENIED: /'; fail=1; else echo "  ok"; fi

# --- 2. Tracked files that ignore rules say should not be tracked ------------
echo "[2/5] Tracked-but-ignored files"
hits=$(git ls-files -ci --exclude-standard)
if [ -n "$hits" ]; then echo "$hits" | sed 's/^/  TRACKED-IGNORED: /'; fail=1; else echo "  ok"; fi

# --- 3. Content and history deny patterns ------------------------------------
echo "[3/5] File contents and commit history vs content deny-list"
if [ -f .git/info/preflight-deny-content ]; then
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    files=$(git grep -Iil -E "$pat" -- . 2>/dev/null)
    if [ -n "$files" ]; then echo "$files" | sed "s/^/  CONTENT ($pat): /"; fail=1; fi
    if git rev-parse -q --verify HEAD >/dev/null 2>&1; then
      if git log --format=%B | grep -qiE "$pat"; then
        echo "  HISTORY ($pat): found in commit messages"; fail=1
      fi
    fi
  done < .git/info/preflight-deny-content
  [ $fail -eq 0 ] && echo "  ok"
else
  echo "  skipped (no content deny-list configured)"
fi

# --- 4. Secret scan -----------------------------------------------------------
echo "[4/5] Secret scan (Trivy)"
if command -v trivy >/dev/null 2>&1; then
  trivy fs --scanners secret --exit-code 1 -q . && echo "  ok" || fail=1
elif command -v docker >/dev/null 2>&1; then
  docker run --rm -v "$PWD:/scan:ro" aquasec/trivy:latest fs --scanners secret --exit-code 1 -q /scan \
    && echo "  ok" || fail=1
else
  echo "  WARNING: trivy and docker unavailable, secret scan skipped"
fi

# --- 5. Terraform hygiene ------------------------------------------------------
echo "[5/5] Terraform fmt/validate"
if [ -d infra/.terraform ]; then
  terraform -chdir=infra fmt -check -recursive >/dev/null || { echo "  fmt check failed"; fail=1; }
  terraform -chdir=infra validate >/dev/null || { echo "  validate failed"; fail=1; }
  [ $fail -eq 0 ] && echo "  ok"
else
  echo "  skipped (infra not initialized)"
fi

echo
if [ $fail -eq 0 ]; then echo "PREFLIGHT PASSED"; else echo "PREFLIGHT FAILED"; exit 1; fi
