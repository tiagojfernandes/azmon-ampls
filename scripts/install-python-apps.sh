#!/usr/bin/env bash
set -euo pipefail

# Set HOME if not already set (needed for VM custom script extension)
export HOME=${HOME:-/home/azureuser}

if [[ $# -lt 1 ]]; then
  cat <<EOF
Usage: $0 <APPLICATION_INSIGHTS_CONNECTION_STRING>
Deploys Flask Sample App with App Insights instrumentation for Python
EOF
  exit 1
fi

AI_CONN_STR="$1"

# export for all sessions
sudo tee -a /etc/environment <<EOF
APPLICATIONINSIGHTS_CONNECTION_STRING=$AI_CONN_STR
EOF

BASE_DIR="/home/azureuser/flask-sample"
echo "Creating base directory at $BASE_DIR"
mkdir -p "$BASE_DIR"

echo "→ Deploying Flask Sample App to $BASE_DIR"

sudo apt-get update -y
sudo apt-get install -y python3-venv python3-pip curl unzip

python3 -m venv "$BASE_DIR/.venv"
source "$BASE_DIR/.venv/bin/activate"
pip install --upgrade pip

pip install \
  azure-monitor-opentelemetry

cat > "$BASE_DIR/flask_app.py" <<'EOF'
from azure.monitor.opentelemetry import configure_azure_monitor

from random import randint
import logging
from opentelemetry import trace

conn_str = os.environ["APPLICATIONINSIGHTS_CONNECTION_STRING"]

configure_azure_monitor(
	connection_string=conn_str,
)

from flask import Flask, request

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Endpoint to simulate a dice roll. Accepts an optional 'player' query parameter.
# Logs the result of the dice roll, including the player's name if provided.
# Returns the result of the dice roll as a string.
@app.route("/rolldice")
def roll_dice():
    player = request.args.get('player', default = None, type = str)
    result = str(roll())
    if player:
        logger.warning("%s is rolling the dice: %s", player, result)
    else:
        logger.warning("Anonymous player is rolling the dice: %s", result)
    return result

# Exceptions that are raised within the request are automatically captured
@app.route("/exception")
def exception():
    raise Exception("Hit an exception")

def roll():
    return randint(1, 6)

if __name__ == "__main__":
    app.run(host="localhost", port=5000)
    roll_dice()
EOF

pyrhon3 "$BASE_DIR/python3" flask_app.py &

echo "→ Flask Sample App up on port 5000."


# Creating the cron job
echo "Creating jobs to call Flask app every 15s."

# ─── Add every‑15s cron jobs ────────────────────────────────────────────────
CRON_TMP=$(mktemp)
crontab -l 2>/dev/null > "$CRON_TMP" || true

# 1) Cron job for Flask
if ! grep -q "CALL_FLASK_APP_15S" "$CRON_TMP"; then
  cat >> "$CRON_TMP" <<'EOF'
# CALL_FLASK_APP_15S: hit Flask endpoints 4/min (every 15s)
SHELL=/bin/bash
* * * * * . /etc/environment && for i in {1..4}; do \
  curl -s "http://127.0.0.1:5000/rolldice?player=Player1" > /dev/null; \
  curl -s "http://127.0.0.1:5000/exception" > /dev/null; \
  sleep 15; \
done
EOF
  crontab "$CRON_TMP"
  echo "Cron job added successfully."
else
  echo "Cron job already exists."
fi

rm "$CRON_TMP"

echo "Cron jobs updated to call Flask app every 15s."
