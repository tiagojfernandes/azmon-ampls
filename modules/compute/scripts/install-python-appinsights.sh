#!/usr/bin/env bash
set -e

AI_CONN_STR="${AI_CONN_STR}"

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
