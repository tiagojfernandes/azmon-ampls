#!/usr/bin/env bash
set -euo pipefail

# Set HOME if not already set (needed for VM custom script extension)
export HOME=${HOME:-/home/azureuser}

if [[ $# -lt 1 ]]; then
  cat <<EOF
Usage: $0 <APPLICATION_INSIGHTS_CONNECTION_STRING>
Deploys two samples:
  1) Flask app with CLI-based OpenTelemetry injection  
  2) Manual Python “workload” with hand-wired traces/metrics/logs

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


###### Manual Sample #########

python3 -m venv "$MANUALDIR/.venv"
source "$MANUALDIR/.venv/bin/activate"

pip install --upgrade pip
pip install \
  opentelemetry-api \
  opentelemetry-sdk \
  azure-monitor-opentelemetry-exporter

cat > "$MANUALDIR/app.py" <<'EOF'
import os, time, logging
from random import random
from opentelemetry import trace, metrics
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from azure.monitor.opentelemetry.exporter import (
    AzureMonitorTraceExporter,
    AzureMonitorMetricExporter
)

# setup
conn_str = os.environ["APPLICATIONINSIGHTS_CONNECTION_STRING"]
resource = Resource.create({"service.name": "manual-sample"})

# tracing
tp = TracerProvider(resource=resource)
tp.add_span_processor(BatchSpanProcessor(AzureMonitorTraceExporter(connection_string=conn_str)))
trace.set_tracer_provider(tp)
tracer = trace.get_tracer(__name__)

# metrics
mr = PeriodicExportingMetricReader(
       exporter=AzureMonitorMetricExporter(connection_string=conn_str),
       export_interval_millis=10000)
mp = MeterProvider(resource=resource, metric_readers=[mr])
metrics.set_meter_provider(mp)
meter = metrics.get_meter(__name__)
counter = meter.create_counter("work.iterations")

# logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("manual")

def work(i):
    with tracer.start_as_current_span("iter-span"):
        counter.add(1, {"iteration": i})
        logger.info(f"Iteration {i} done")
        time.sleep(1)

if __name__ == "__main__":
    for i in range(4):
        work(i)
EOF

nohup python3 "$MANUALDIR/app.py" > "$MANUALDIR/app.log" 2>&1 &

echo "→ Manual app running; check app.log for output."

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

# 2) Cron job for manual sample (using the venv Python)
if ! grep -q "CALL_MANUAL_APP_15S" "$CRON_TMP"; then
cat >> "$CRON_TMP" <<'EOF'
# CALL_MANUAL_APP_15S: run manual sample 4/min (every 15s)
SHELL=/bin/bash
* * * * * . /etc/environment && for i in {1..4}; do nohup "/home/azureuser/otel-samples/manual-samples/.venv/bin/python" "/home/azureuser/otel-samples/manual-samples/app.py" > "/home/azureuser/otel-samples/manual-samples/app.log" 2>&1; sleep 15; done
EOF
fi

crontab "$CRON_TMP"
rm "$CRON_TMP"
echo "Cron jobs updated to call both apps every 15s."
