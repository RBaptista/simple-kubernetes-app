# Pinned minor version: patch updates (3.14.x) are fine, 3.15 is a deliberate choice
FROM python:3.14-alpine

WORKDIR /usr/src/app

# Install dependencies first: this layer is cached until requirements.txt changes,
# so editing main.py doesn't trigger a full pip install again
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Run as an unprivileged user instead of root
RUN adduser -D app
USER app

EXPOSE 5000
CMD ["python", "main.py"]
