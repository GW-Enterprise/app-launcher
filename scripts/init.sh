#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<-EOSQL

-- ===============================
-- Replication user
-- ===============================
DO \$\$
BEGIN
  IF NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname = '$REPLICATION_USER'
  ) THEN
    CREATE ROLE $REPLICATION_USER
      WITH REPLICATION LOGIN PASSWORD '$REPLICATION_PASSWORD';
  END IF;
END
\$\$;

-- ===============================
-- Application user
-- ===============================
DO \$\$
BEGIN
  IF NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname = '$DB_SPECIFIC_USER'
  ) THEN
    CREATE USER $DB_SPECIFIC_USER
      WITH PASSWORD '$DB_SPECIFIC_PASSWORD'
      CREATEDB;
  END IF;
END
\$\$;

-- ===============================
-- Database
-- ===============================
DO \$\$
BEGIN
  IF NOT EXISTS (
    SELECT FROM pg_database WHERE datname = '$POSTGRES_DB'
  ) THEN
    CREATE DATABASE $POSTGRES_DB OWNER $DB_SPECIFIC_USER;
  END IF;
END
\$\$;

ALTER DATABASE $POSTGRES_DB OWNER TO $DB_SPECIFIC_USER;

\connect $POSTGRES_DB

-- ===============================
-- Schema & privileges
-- ===============================
ALTER SCHEMA public OWNER TO $DB_SPECIFIC_USER;
GRANT ALL ON SCHEMA public TO $DB_SPECIFIC_USER;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL ON TABLES TO $DB_SPECIFIC_USER;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL ON SEQUENCES TO $DB_SPECIFIC_USER;

EOSQL
