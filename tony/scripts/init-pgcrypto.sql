-- DSpace 7 requires the pgcrypto extension (>=1.1) in the database.
-- This script runs automatically when the PostgreSQL data directory is first created.
\connect dspace
CREATE EXTENSION IF NOT EXISTS pgcrypto;
