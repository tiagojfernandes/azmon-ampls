#!/usr/bin/env bash
set -euo pipefail

AI_CONN_STR="${AI_CONN_STR}"
FLASK_DIR="/home/azureuser/flask-sample"

# 1) Install system dependencies
sudo apt-get update -y
sudo apt-get install -y python3-pip python3-venv unzip

# 2) Create app directory & venv
mkdir -p "$FLASK_DIR"
python3 -m venv "$FLASK_DIR/.venv"

# 3) Activate venv and install Python packages
source "$FLASK_DIR/.venv/bin/activate"
pip install --upgrade pip

pip install \
  flask \
  opentelemetry-api \
  opentelemetry-sdk \
  opentelemetry-instrumentation-flask \
  opentelemetry-instrumentation-requests \
  azure-monitor-opentelemetry-exporter

# 4) Write out the Flask application
cat > "$FLASK_DIR/flask_app.py" <<'EOF'
import os
from flask import Flask, request
import logging
import time

# OpenTelemetry imports
from opentelemetry import trace, metrics
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from azure.monitor.opentelemetry.exporter import AzureMonitorTraceExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor

# Configure tracing
conn_str = os.environ["AZURE_MONITOR_CONNECTION_STRING"]
resource = Resource.create({"service.name": "flask-sample"})
provider = TracerProvider(resource=resource)
exporter = AzureMonitorTraceExporter(connection_string=conn_str)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# Flask app
app = Flask(__name__)
FlaskInstrumentor().instrument_app(app, tracer_provider=provider)

# Set up basic logging (so logs also flow through OTEL)
handler = logging.StreamHandler()
handler.setLevel(logging.INFO)
app.logger.addHandler(handler)
app.logger.setLevel(logging.INFO)

@app.route("/")
def index():
    app.logger.info("Handling index request")
    return "Hello, OpenTelemetry & Flask!"

@app.route("/sleep")
def sleepy():
    app.logger.info("Handling /sleep request, sleeping 0.5s")
    time.sleep(0.5)
    return "Slept half a second"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

# 5) Export connection string and launch under OTEL injector
export AZURE_MONITOR_CONNECTION_STRING="$AI_CONN_STR"

# If you want metrics/logs exporters too, add:
#   --metrics_exporter azure_monitor \
#   --logs_exporter azure_monitor \
nohup opentelemetry-instrument \
  --traces_exporter azure_monitor \
  --connection_string "$AZURE_MONITOR_CONNECTION_STRING" \
  --service_name flask-sample \
  python "$FLASK_DIR/flask_app.py" \
  > "$FLASK_DIR/nohup.out" 2>&1 &

# 6) Wait a few seconds for Flask to start up
sleep 10

# 7) Create a script to generate traffic to the Flask endpoints
cat > "$FLASK_DIR/generate_traffic.sh" <<'EOF'
#!/bin/bash
# Script to generate traffic to Flask endpoints alternately

while true; do
    # Hit the index endpoint
    curl -s http://127.0.0.1:5000/ > /dev/null 2>&1
    sleep 5
    
    # Hit the sleep endpoint
    curl -s http://127.0.0.1:5000/sleep > /dev/null 2>&1
    sleep 5
done
EOF

chmod +x "$FLASK_DIR/generate_traffic.sh"

# 8) Install curl if not present
sudo apt-get install -y curl

# 9) Start the traffic generator in background
nohup "$FLASK_DIR/generate_traffic.sh" > "$FLASK_DIR/traffic.log" 2>&1 &

# 10) Add cron job to ensure traffic generator restarts on reboot
(crontab -l 2>/dev/null; echo "@reboot $FLASK_DIR/generate_traffic.sh > $FLASK_DIR/traffic.log 2>&1 &") | crontab -

echo "Flask app deployed in $FLASK_DIR and running under OpenTelemetry."
echo "Traffic generator started - hitting endpoints every 5 seconds alternately."
echo "Logs & traces will be sent to Application Insights."
