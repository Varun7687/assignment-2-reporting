#!/usr/bin/env bash
# Configure the Northwind reporting script and 15-minute cron job on an existing EC2 reporting server.
# This does NOT provision VPC, NAT, EC2, S3, IAM, or SNS resources.
set -euo pipefail
umask 077

EXPECTED_USER="ec2-user"
if [[ "$(id -un)" != "$EXPECTED_USER" ]]; then
  echo "ERROR: Run this as ${EXPECTED_USER}, not root." >&2
  echo "Example: su - ec2-user && bash /path/to/setup.sh" >&2
  exit 1
fi

AWS_REGION="${AWS_REGION:-us-east-1}"
REPORT_BUCKET="${REPORT_BUCKET:-northwind-reporting-reports}"
SNS_TOPIC_NAME="${SNS_TOPIC_NAME:-nightly-report-ready}"

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: AWS CLI is not installed or not in PATH." >&2
  exit 1
fi

if [[ -e "${HOME}/.aws/credentials" || -L "${HOME}/.aws/credentials" ]]; then
  echo "ERROR: ${HOME}/.aws/credentials exists. Remove static credentials and use the EC2 IAM role." >&2
  exit 1
fi

for name in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE AWS_DEFAULT_PROFILE; do
  if [[ -n "${!name:-}" ]]; then
    echo "ERROR: ${name} is set. Unset static/profile credentials and use the EC2 IAM role." >&2
    exit 1
  fi
done

CALLER_ARN="$(aws sts get-caller-identity --query Arn --output text --region "$AWS_REGION")"
case "$CALLER_ARN" in
  arn:aws:sts::*:assumed-role/*) ;;
  *)
    echo "ERROR: Expected EC2 assumed-role credentials; AWS returned: ${CALLER_ARN}" >&2
    exit 1
    ;;
esac
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text --region "$AWS_REGION")"
SNS_TOPIC_ARN="${SNS_TOPIC_ARN:-arn:aws:sns:${AWS_REGION}:${ACCOUNT_ID}:${SNS_TOPIC_NAME}}"

PROJECT_DIR="${HOME}/assignment-2-reporting"
SCRIPT_DIR="${PROJECT_DIR}/scripts"
REPORT_SCRIPT="${SCRIPT_DIR}/generate_report.sh"
LOG_FILE="${HOME}/generate_report.log"

# Ensure ec2-user owns the project directory, including any directory previously created as root.
sudo mkdir -p "$SCRIPT_DIR"
sudo chown -R "${EXPECTED_USER}:${EXPECTED_USER}" "$PROJECT_DIR"

cat > "$REPORT_SCRIPT" <<'REPORT_SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077

AWS_REGION="${AWS_REGION:-us-east-1}"
REPORT_BUCKET="${REPORT_BUCKET:-northwind-reporting-reports}"
SNS_TOPIC_ARN="${SNS_TOPIC_ARN:?Set SNS_TOPIC_ARN to the full nightly-report-ready topic ARN}"

if [[ -e "${HOME}/.aws/credentials" || -L "${HOME}/.aws/credentials" ]]; then
  echo "ERROR: ${HOME}/.aws/credentials exists. Use the EC2 IAM role instead." >&2
  exit 1
fi

for name in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE AWS_DEFAULT_PROFILE; do
  if [[ -n "${!name:-}" ]]; then
    echo "ERROR: ${name} is set. Unset it and use the EC2 IAM role." >&2
    exit 1
  fi
done

CALLER_ARN="$(aws sts get-caller-identity --query Arn --output text --region "$AWS_REGION")"
case "$CALLER_ARN" in
  arn:aws:sts::*:assumed-role/*) ;;
  *)
    echo "ERROR: Expected EC2 assumed-role credentials; AWS returned identity: ${CALLER_ARN}" >&2
    exit 1
    ;;
esac

REPORT_DATE="$(date +%F)"
HOST="$(hostname -f 2>/dev/null || hostname)"
DISK_USAGE="$(df -hP / | awk 'NR==2 {printf "%s used of %s (%s), %s available", $3, $2, $5, $4}')"
REPORT_DIR="${REPORT_DIR:-${HOME}/reports}"
REPORT_FILE="${REPORT_DIR}/${REPORT_DATE}.txt"
S3_KEY="reports/${REPORT_DATE}.txt"

mkdir -p "$REPORT_DIR"
cat > "$REPORT_FILE" <<REPORT_EOF
Date: ${REPORT_DATE}
Hostname: ${HOST}
Disk usage for /: ${DISK_USAGE}

Fake sales figures (test data):
Product A: \$1,250.00
Product B: \$980.50
Product C: \$1,475.25
REPORT_EOF

aws s3 cp "$REPORT_FILE" "s3://${REPORT_BUCKET}/${S3_KEY}" \
  --region "$AWS_REGION" --no-progress

aws sns publish \
  --topic-arn "$SNS_TOPIC_ARN" \
  --subject "Test sales report ready: ${REPORT_DATE}" \
  --message "Report uploaded to s3://${REPORT_BUCKET}/${S3_KEY}. Object key: ${S3_KEY}" \
  --region "$AWS_REGION" \
  --query 'MessageId' --output text

printf 'Uploaded s3://%s/%s and published SNS notification.\n' "$REPORT_BUCKET" "$S3_KEY"
REPORT_SCRIPT_EOF

chmod 750 "$REPORT_SCRIPT"
bash -n "$REPORT_SCRIPT"

if ! command -v crontab >/dev/null 2>&1; then
  sudo dnf install -y cronie
fi
sudo systemctl enable --now crond

CRON_TMP="$(mktemp)"
CURRENT_CRON="$(crontab -l 2>/dev/null || true)"
printf '%s\n' "$CURRENT_CRON" | awk '
  $0 == "# BEGIN NORTHWIND REPORTING" { skip = 1; next }
  $0 == "# END NORTHWIND REPORTING" { skip = 0; next }
  !skip { print }
' > "$CRON_TMP"
{
  printf '\n# BEGIN NORTHWIND REPORTING\n'
  printf '*/15 * * * * AWS_REGION=%s REPORT_BUCKET=%s SNS_TOPIC_ARN="%s" %s >> %s 2>&1\n' \
    "$AWS_REGION" "$REPORT_BUCKET" "$SNS_TOPIC_ARN" "$REPORT_SCRIPT" "$LOG_FILE"
  printf '# END NORTHWIND REPORTING\n'
} >> "$CRON_TMP"
crontab "$CRON_TMP"
rm -f "$CRON_TMP"

printf '\nSetup complete for user %s.\n' "$EXPECTED_USER"
printf 'Report script: %s\n' "$REPORT_SCRIPT"
printf 'Cron schedule: every 15 minutes\n'
printf 'Log file: %s\n' "$LOG_FILE"
printf 'AWS region: %s\nBucket: %s\nSNS topic: %s\n' "$AWS_REGION" "$REPORT_BUCKET" "$SNS_TOPIC_ARN"
printf '\nVerify with: crontab -l\n'
printf 'After a scheduled run, check: tail -n 30 %s\n' "$LOG_FILE"
printf '\nEach successful run uploads the dated report and publishes an SNS notification.\n'
