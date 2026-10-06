# Sandbox for executing model-generated SpreadsheetBench code (see patches/spreadsheet_docker_sandbox.patch).
# Mirrors the spreadsheet libraries of the host training venv so generated code behaves identically.
FROM python:3.12-slim
RUN pip install --no-cache-dir openpyxl==3.1.5 pandas==3.0.6 numpy==2.5.3 python-dateutil==2.9.0.post0 et_xmlfile==2.0.0
WORKDIR /sandbox
