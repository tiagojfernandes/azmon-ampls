#!/usr/bin/env bash
set -euo pipefail

# Set HOME if not already set (needed for VM custom script extension)
export HOME=${HOME:-/home/azureuser}

if [[ $# -lt 1 ]]; then
  cat <<EOF
Usage: $0 <APPLICATION_INSIGHTS_CONNECTION_STRING>
Deploys Flask app with CLI-based OpenTelemetry injection  

Both will restart on reboot via cron.
EOF
  exit 1
fi

AI_CONN_STR="$1"

# export for all sessions
sudo tee -a /etc/environment <<EOF
APPLICATIONINSIGHTS_CONNECTION_STRING=$AI_CONN_STR
EOF


BASE_DIR="/home/azureuser/otel-samples"
echo "Creating base directory at $BASE_DIR"
mkdir -p "$BASE_DIR"

FLASKDIR="$BASE_DIR/flask-samples"
mkdir -p "$FLASKDIR"

MANUALDIR="$BASE_DIR/manual-samples"
mkdir -p "$MANUALDIR"

echo "→ Deploying Flask (CLI instrumentation) to $FLASKDIR"

sudo apt-get update -y
sudo apt-get install -y python3-venv python3-pip curl unzip

python3 -m venv "$FLASKDIR/.venv"
source "$FLASKDIR/.venv/bin/activate"
pip install --upgrade pip

pip install \
  flask \
  opentelemetry-api \
  opentelemetry-sdk \
  opentelemetry-instrumentation-flask \
  opentelemetry-instrumentation-requests \
  azure-monitor-opentelemetry-exporter

cat > "$FLASKDIR/flask_app.py" <<'EOF'
from flask import Flask
app = Flask(__name__)

@app.route("/")
def index():
    return "Hello from CLI-instrumented Flask!"
    
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

nohup opentelemetry-instrument \
  --traces_exporter azure_monitor \
  --service_name flask-cli-sample \
  python "$FLASKDIR/flask_app.py" \
  >"$FLASKDIR/nohup.out" 2>&1 &

echo "→ Flask (CLI) up on port 5000."

# creating the cron jobs
echo "Creating jobs to call both apps every 15s."

# ─── Add every‑15s cron jobs ────────────────────────────────────────────────
CRON_TMP=$(mktemp)
crontab -l 2>/dev/null > "$CRON_TMP" || true

# 1) Cron job for Flask (assuming port 5000)
if ! grep -q "CALL_FLASK_APP_15S" "$CRON_TMP"; then
  cat >> "$CRON_TMP" <<'EOF'
# CALL_FLASK_APP_15S: hit Flask endpoint 4/min (every 15s)
SHELL=/bin/bash
* * * * * . /etc/environment && for i in {1..4}; do curl -s http://127.0.0.1:5000/ > /dev/null; sleep 15; done
EOF
fi

crontab "$CRON_TMP"
rm "$CRON_TMP"
echo "Cron jobs updated to call both apps every 15s."
