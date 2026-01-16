#!/bin/sh
set -e

echo "Starting container..."

if [ -z "$DATABASE_URL" ]; then
  echo "DATABASE_URL not set, skipping migrations"
else
  echo "Running Prisma migrations..."
  ./node_modules/.bin/prisma migrate deploy

fi

exec "$@"
