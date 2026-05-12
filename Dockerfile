FROM parseable/parseable:edge

ENV P_ADDR=0.0.0.0:8000
ENV P_STAGING_DIR=/data/staging

EXPOSE 8000

# This Dockerfile is shared by both the query and ingest services.
# The two services are differentiated by env vars injected via the Railway template:
#
# Shared (both services):
#   From Railway Bucket (variable references):
#     P_S3_URL        -> Bucket ENDPOINT
#     P_S3_ACCESS_KEY -> Bucket ACCESS_KEY_ID
#     P_S3_SECRET_KEY -> Bucket SECRET_ACCESS_KEY
#     P_S3_BUCKET     -> Bucket BUCKET
#     P_S3_REGION     -> Bucket REGION
#   User-configured (set on query, referenced from ingest):
#     P_USERNAME      -> admin username
#     P_PASSWORD      -> admin password (auto-generated)
#
# Query service only:
#   P_MODE=query
#
# Ingest service only:
#   P_MODE=ingest
#   P_INGESTOR_ENDPOINT -> ${{RAILWAY_PRIVATE_DOMAIN}}:8000
#
# Both services bind to PORT=8000 to align with Railway routing/healthcheck.
