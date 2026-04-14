#!/bin/sh
set -e

echo "Waiting for Postgres to be ready..."
until pg_isready -U "$POSTGRES_USER" -d postgres; do
  sleep 1
done

echo "Postgres is ready. Running init script..."

# Replication user
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -c "
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${REPLICATION_USER}') THEN
    CREATE ROLE \"${REPLICATION_USER}\" WITH REPLICATION LOGIN PASSWORD '${REPLICATION_PASSWORD}';
  END IF;
END
\$\$;"

# Application user
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres -c "
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_SPECIFIC_USER}') THEN
    CREATE ROLE \"${DB_SPECIFIC_USER}\" LOGIN PASSWORD '${DB_SPECIFIC_PASSWORD}' CREATEDB;
  ELSE
    ALTER ROLE \"${DB_SPECIFIC_USER}\" WITH PASSWORD '${DB_SPECIFIC_PASSWORD}';
  END IF;
END
\$\$;"

# Database
DB_EXISTS=$(psql -U "$POSTGRES_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '${POSTGRES_DB}'")
if [ "$DB_EXISTS" != "1" ]; then
  echo "Creating database ${POSTGRES_DB}..."
  psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE \"${POSTGRES_DB}\" OWNER \"${DB_SPECIFIC_USER}\";"
else
  echo "Database ${POSTGRES_DB} already exists. Ensuring ownership..."
  psql -U "$POSTGRES_USER" -d postgres -c "ALTER DATABASE \"${POSTGRES_DB}\" OWNER TO \"${DB_SPECIFIC_USER}\";"
fi

# Schema & privileges
psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
ALTER SCHEMA public OWNER TO \"${DB_SPECIFIC_USER}\";
GRANT ALL ON SCHEMA public TO \"${DB_SPECIFIC_USER}\";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO \"${DB_SPECIFIC_USER}\";
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO \"${DB_SPECIFIC_USER}\";"

echo "Init complete."