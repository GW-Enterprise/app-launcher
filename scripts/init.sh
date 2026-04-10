#!/bin/sh
set -e

# echo "Waiting for Postgres to be ready..."

# until pg_isready -h localhost -U "$POSTGRES_USER" -d postgres; do
#   sleep 2
# done

echo "Postgres is ready. Running init script..."

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "postgres" <<EOSQL

-- ===============================
-- Replication user
-- ===============================
DO \$\$
BEGIN
  IF NOT EXISTS (
    SELECT FROM pg_roles WHERE rolname = '$REPLICATION_USER'
  ) THEN
    EXECUTE format(
      'CREATE ROLE %I WITH REPLICATION LOGIN PASSWORD %L',
      '$REPLICATION_USER',
      '$REPLICATION_PASSWORD'
    );
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
    EXECUTE format(
      'CREATE ROLE %I LOGIN PASSWORD %L CREATEDB',
      '$DB_SPECIFIC_USER',
      '$DB_SPECIFIC_PASSWORD'
    );
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
    EXECUTE format(
      'CREATE DATABASE %I OWNER %I',
      '$POSTGRES_DB',
      '$DB_SPECIFIC_USER'
    );
  END IF;
END
\$\$;

ALTER DATABASE "$POSTGRES_DB" OWNER TO "$DB_SPECIFIC_USER";

\connect "$POSTGRES_DB"

-- ===============================
-- Schema & privileges
-- ===============================
ALTER SCHEMA public OWNER TO "$DB_SPECIFIC_USER";
GRANT ALL ON SCHEMA public TO "$DB_SPECIFIC_USER";

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL ON TABLES TO "$DB_SPECIFIC_USER";

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL ON SEQUENCES TO "$DB_SPECIFIC_USER";

EOSQL

echo "Init complete."
