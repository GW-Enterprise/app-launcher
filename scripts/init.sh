#!/bin/sh
set -e
export PGPASSWORD=$POSTGRES_PASSWORD

echo "Waiting for Postgres to be ready..."

# We use pg_isready without -h localhost because during init,
# Postgres might not be accepting TCP connections yet, but unix sockets work.
until pg_isready -U "$POSTGRES_USER" -d postgres; do
  sleep 1
done

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
  ELSE
    EXECUTE format(
      'ALTER ROLE %I WITH PASSWORD %L',
      '$DB_SPECIFIC_USER',
      '$DB_SPECIFIC_PASSWORD'
    );
  END IF;
END
\$\$;
EOSQL

# ===============================
# Database creation (Outside DO block)
# ===============================
DB_EXISTS=$(psql -U "$POSTGRES_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$POSTGRES_DB'")

if [ "$DB_EXISTS" != "1" ]; then
  echo "Creating database $POSTGRES_DB..."
  psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE \"$POSTGRES_DB\" OWNER \"$DB_SPECIFIC_USER\";"
else
  echo "Database $POSTGRES_DB already exists."
fi

# ===============================
# Schema & privileges (Connecting to the specific DB)
# ===============================
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
ALTER SCHEMA public OWNER TO "$DB_SPECIFIC_USER";
GRANT ALL ON SCHEMA public TO "$DB_SPECIFIC_USER";

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL ON TABLES TO "$DB_SPECIFIC_USER";

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT ALL ON SEQUENCES TO "$DB_SPECIFIC_USER";
EOSQL


echo "Init complete."
