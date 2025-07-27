#!/bin/bash
# Install Python OpenTelemetry and Flask applications with Application Insights
# This script sets up Python apps that send telemetry to Azure Application Insights

set -e  # Exit on any error

APPLICATION_INSIGHTS_CONNECTION_STRING="$1"

if [ -z "$APPLICATION_INSIGHTS_CONNECTION_STRING" ]; then
    echo "ERROR: Application Insights connection string is required as first parameter"
    exit 1
fi

echo "Starting Python OpenTelemetry and Flask setup..."

sudo apt-get update -y
sudo apt-get install -y python3-pip

# install tracing + metrics + logging exporters & instrumentations
pip3 install \
  opentelemetry-api \
  opentelemetry-sdk \
  opentelemetry-sdk-metrics \
  opentelemetry-sdk-logs \
  azure-monitor-opentelemetry-exporter \
  opentelemetry-instrumentation-requests

# drop in the enhanced app
cat > ~/app.py <<'EOF'
import os, logging
from time import sleep
from random import random

# OpenTelemetry core
from opentelemetry import trace, metrics
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk._logs import LoggerProvider, BatchLogProcessor
from opentelemetry.sdk._logs.export import ConsoleLogExporter

# Azure Monitor exporters
from azure.monitor.opentelemetry.exporter import (
    AzureMonitorTraceExporter,
    AzureMonitorMetricExporter,
    AzureMonitorLogExporter
)

# 1) common setup
conn_str = os.environ.get("AZURE_MONITOR_CONNECTION_STRING", "$AI_CONN_STR")
resource = Resource.create({"service.name": "terraform-linux-sample"})

# 2) TRACE setup
trace_provider = TracerProvider(resource=resource)
trace_exporter = AzureMonitorTraceExporter(connection_string=conn_str)
trace_provider.add_span_processor(BatchSpanProcessor(trace_exporter))
trace.set_tracer_provider(trace_provider)
tracer = trace.get_tracer(__name__)

# 3) METRICS setup
metric_exporter = AzureMonitorMetricExporter(connection_string=conn_str)
metric_reader   = PeriodicExportingMetricReader(exporter=metric_exporter, export_interval_millis=60000)
meter_provider  = MeterProvider(resource=resource, metric_readers=[metric_reader])
metrics.set_meter_provider(meter_provider)
meter = metrics.get_meter(__name__)
counter = meter.create_counter("example.counter", description="An example counter")

# 4) LOGS setup
logger_provider = LoggerProvider(resource=resource)
log_exporter    = AzureMonitorLogExporter(connection_string=conn_str)
logger_provider.add_log_processor(BatchLogProcessor(log_exporter))
# optional: also print to console while testing
logger_provider.add_log_processor(BatchLogProcessor(ConsoleLogExporter()))
from opentelemetry.sdk._logs import LoggingHandler
handler = LoggingHandler(level=logging.INFO, logger_provider=logger_provider)
logging.getLogger().setLevel(logging.INFO)
logging.getLogger().addHandler(handler)
logger = logging.getLogger("sample")

# 5) workload
def do_work(iteration):
    with tracer.start_as_current_span("work-span") as span:
        span.set_attribute("work.iteration", iteration)
        counter.add(1, {"iteration": iteration})
        logger.info(f"Iteration {iteration}: counter bumped")
        sleep(1)

if __name__ == "__main__":
    for i in range(10):
        do_work(i)
EOF

# kick off in background
export AZURE_MONITOR_CONNECTION_STRING="$AI_CONN_STR"
nohup python3 ~/app.py >/dev/null 2>&1 &

# Add cron job to ensure Python app restarts on reboot
(crontab -l 2>/dev/null; echo "@reboot export AZURE_MONITOR_CONNECTION_STRING='$AI_CONN_STR' && nohup python3 ~/app.py >/dev/null 2>&1 &") | crontab -

echo "Python OpenTelemetry app deployed and running in background."
echo "App will restart automatically on reboot via cron job."
echo "Traces, metrics, and logs will be sent to Application Insights."

# Install Flask app with OpenTelemetry and Application Insights
echo "Setting up Flask app with OpenTelemetry and Application Insights..."

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
