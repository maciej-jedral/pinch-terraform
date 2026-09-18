#!/usr/bin/env bash
# Runs Terraform inside Docker so nothing needs to be installed on the host.
#
# Usage: ./tf <any terraform args>
#   ./tf init                       # root module (auto-adds -backend-config=backend.hcl if present)
#   ./tf plan
#   ./tf apply
#   ./tf -chdir=bootstrap init      # the state-bucket bootstrap module
#
# What gets mounted / passed in:
#   - this directory      -> /work   (the Terraform code, .terraform/, lock file)
#   - ~/.aws (read-only)  -> /root/.aws  (AWS credentials + config; the container runs as root)
#   - NEON_API_KEY, PORKBUN_API_KEY, PORKBUN_SECRET_KEY
#                         -> from your shell or from ./.env (gitignored)
#   - AWS_PROFILE/REGION  -> passed through if set
set -euo pipefail

TF_VERSION="1.16.2"

cd "$(dirname "$0")"

# .env is the local, gitignored place for secrets like NEON_API_KEY.
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

args=("$@")

# For `./tf init` in the root module, pick up the gitignored backend.hcl automatically
# so the state bucket name (which contains the AWS account id) never lands in git.
if [ "${1:-}" = "init" ] && [ -f backend.hcl ]; then
  args+=(-backend-config=backend.hcl)
fi

tty_flags=()
if [ -t 0 ]; then
  tty_flags=(-it)
fi

exec docker run --rm "${tty_flags[@]}" \
  -v "$PWD":/work \
  -w /work \
  -v "$HOME/.aws":/root/.aws:ro \
  -e AWS_PROFILE \
  -e AWS_REGION \
  -e NEON_API_KEY \
  -e PORKBUN_API_KEY \
  -e PORKBUN_SECRET_KEY \
  -e TF_LOG \
  "hashicorp/terraform:${TF_VERSION}" "${args[@]}"
