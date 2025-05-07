# Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY *.py .
COPY templates templates/

# Create data directory for database
RUN mkdir -p /app/data

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV FLASK_APP=app.py
ENV SECRET_KEY=change_this_to_a_random_secret

# Expose port
EXPOSE 5000

# Run the application
CMD ["python", "app.py"]
