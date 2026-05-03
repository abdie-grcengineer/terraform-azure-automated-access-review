# Container image for the Azure Access Review job.
# Built and pushed to Azure Container Registry by the GitHub Actions workflow.
# Container Apps Jobs schedule a one-shot run of this container; the job exits
# with code 0 on success, non-zero on failure. stdout/stderr go to Log Analytics.

FROM python:3.11-slim

WORKDIR /app

# Install Python dependencies first so the layer is cached when only code changes.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the application code.
COPY . .

# main.py is the entrypoint. The container exits when main() returns.
CMD ["python", "main.py"]
