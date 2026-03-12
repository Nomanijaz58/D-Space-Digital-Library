FROM python:3.9-slim

WORKDIR /app

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the API code
COPY api /app/api

# Expose the API port
EXPOSE 5001

# Run the Flask app with gunicorn
CMD ["gunicorn", "-b", "0.0.0.0:5001", "--chdir", "/app/api", "app:app"]
