#!/usr/bin/env bash
# One-time bootstrap script — automates all manual setup steps before the first CI run.
# After this completes, everything is driven by CI and Flux. You never run this again.
#
# Prerequisites (must be done manually before running):
#   gcloud auth login
#   gcloud auth application-default login
#   gh auth login
#
# Optional env var overrides:
#   REGION          — GCP region (default: europe-west1)
#   TF_STATE_BUCKET — GCS bucket name (default: <project-id>-tfstate)
#   ADMIN_CIDR      — CIDR for k8s API access (default: your current public IP/32)
#   SUBNET_CIDR     — cluster subnet CIDR (default: 10.0.0.0/24)
#   GITHUB_REPO     — repository name (default: enclaive-platform-challenge)
#   SSH_KEY_PATH    — path to SSH key (default: ~/.ssh/enclaive-ci)

set -euo pipefail

# Resolve repo root regardless of where the script is called from
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
step()  { echo -e "\n${GREEN}▶ $1${NC}"; }

# ── prerequisites ─────────────────────────────────────────────────────────────
step "Checking prerequisites"
for cmd in gcloud terraform gh curl ssh-keygen; do
  command -v "$cmd" &>/dev/null || error "'$cmd' not found. See docs/deployment-guide.md for install instructions."
done

gcloud auth print-access-token &>/dev/null 2>&1 \
  || error "Not authenticated to GCP. Run:\n  gcloud auth login\n  gcloud auth application-default login"

gh auth status &>/dev/null 2>&1 \
  || error "Not authenticated to GitHub CLI. Run: gh auth login"

info "All prerequisites satisfied ✅"

# ── gather configuration ──────────────────────────────────────────────────────
step "Gathering configuration"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
[[ -z "$PROJECT_ID" ]] && error "No GCP project set. Run: gcloud config set project <project-id>"
info "GCP project:    $PROJECT_ID"

REGION="${REGION:-europe-west1}"
info "Region:         $REGION"

TF_STATE_BUCKET="${TF_STATE_BUCKET:-${PROJECT_ID}-tfstate}"
info "State bucket:   gs://$TF_STATE_BUCKET"

ADMIN_CIDR="${ADMIN_CIDR:-$(curl -s ifconfig.me)/32}"
info "Admin CIDR:     $ADMIN_CIDR (k8s API access — override with ADMIN_CIDR env var)"

GITHUB_OWNER=$(gh api user --jq .login)
info "GitHub owner:   $GITHUB_OWNER"

GITHUB_REPO="${GITHUB_REPO:-enclaive-platform-challenge}"
info "GitHub repo:    $GITHUB_REPO"

SUBNET_CIDR="${SUBNET_CIDR:-10.0.0.0/24}"
info "Subnet CIDR:    $SUBNET_CIDR"

SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/enclaive-ci}"

# ── GCS state bucket ──────────────────────────────────────────────────────────
step "Creating Terraform state bucket"
if gcloud storage buckets describe "gs://$TF_STATE_BUCKET" &>/dev/null 2>&1; then
  info "Bucket already exists, skipping."
else
  gcloud storage buckets create "gs://$TF_STATE_BUCKET" \
    --location="$REGION" \
    --uniform-bucket-level-access
  info "Bucket created ✅"
fi

# ── SSH key pair ──────────────────────────────────────────────────────────────
step "Generating SSH key pair"
if [[ -f "$SSH_KEY_PATH" ]]; then
  info "Key already exists at $SSH_KEY_PATH, reusing."
else
  ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -q
  info "SSH key generated at $SSH_KEY_PATH ✅"
fi
SSH_PUBLIC_KEY=$(cat "${SSH_KEY_PATH}.pub")

# ── terraform.tfvars ──────────────────────────────────────────────────────────
step "Writing terraform/bootstrap/terraform.tfvars"
# github_token is passed via TF_VAR_ env var — not written to disk to avoid accidental exposure
cat > terraform/bootstrap/terraform.tfvars <<EOF
project_id      = "$PROJECT_ID"
region          = "$REGION"
github_owner    = "$GITHUB_OWNER"
github_repo     = "$GITHUB_REPO"
tf_state_bucket = "$TF_STATE_BUCKET"
admin_cidr      = "$ADMIN_CIDR"
subnet_cidr     = "$SUBNET_CIDR"
ssh_public_key  = "$SSH_PUBLIC_KEY"
EOF
info "terraform.tfvars written (gitignored — will not be committed) ✅"

# ── bootstrap Terraform ───────────────────────────────────────────────────────
step "Running bootstrap Terraform"
# github_token passed via env var so it never touches the filesystem
export TF_VAR_github_token
TF_VAR_github_token=$(gh auth token)

cd terraform/bootstrap
terraform init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="prefix=bootstrap" \
  -input=false
terraform apply -auto-approve -input=false
cd "$REPO_ROOT"
info "Bootstrap Terraform complete ✅"

# ── SSH private key → GitHub secret ──────────────────────────────────────────
step "Setting SSH_PRIVATE_KEY in GitHub Actions secrets"
# Set via gh CLI directly — the private key never passes through Terraform or its state
gh secret set SSH_PRIVATE_KEY \
  --repo "$GITHUB_OWNER/$GITHUB_REPO" \
  --body "$(cat "$SSH_KEY_PATH")"
info "SSH_PRIVATE_KEY set ✅"

# ── done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}🎉 Bootstrap complete!${NC}"
echo ""
info "All GitHub Actions secrets are now populated."
info "Next step: open a PR touching terraform/ or ansible/ and merge it to main."
info "CI will provision the GCE nodes, install k3s, and bootstrap Flux automatically."
echo ""
info "Monitor the run at: https://github.com/$GITHUB_OWNER/$GITHUB_REPO/actions"
