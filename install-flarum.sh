#!/bin/bash
set -e

cd /var/www/html

# Wait for database to be ready
echo "Waiting for database to be ready..."
sleep 10

# Check if Flarum is already installed (if config.php exists)
if [ ! -f config.php ]; then
    echo "Flarum not found. Starting automatic installation..."

    # Test database connection first
    echo "Testing PostgreSQL database connection..."
    PGPASSWORD="${DATABASE_PASSWORD}" psql -h "${DATABASE_HOST}" -U "${DATABASE_USER}" -d "${DATABASE_NAME}" -c "SELECT 1;" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "Database connection successful!"
    else
        echo "ERROR: Cannot connect to PostgreSQL database!"
        echo "Host: ${DATABASE_HOST}"
        echo "User: ${DATABASE_USER}"
        echo "Database: ${DATABASE_NAME}"
        exit 1
    fi

    # Check if database is empty
    echo "Checking if database is empty..."
    TABLE_COUNT=$(PGPASSWORD="${DATABASE_PASSWORD}" psql -h "${DATABASE_HOST}" -U "${DATABASE_USER}" -d "${DATABASE_NAME}" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';")
    
    if [ "$TABLE_COUNT" -gt 0 ]; then
        echo "WARNING: Database already contains $TABLE_COUNT tables!"
        echo "This might cause migration conflicts. Consider using an empty database."
    else
        echo "Database is empty, good to proceed."
    fi

    # Manually create the config.php file for PostgreSQL
    echo "Creating Flarum configuration..."
    cat > config.php << EOF
<?php return array (
  'debug' => false,
  'database' => 
  array (
    'driver' => 'pgsql',
    'host' => '${DATABASE_HOST}',
    'port' => 5432,
    'database' => '${DATABASE_NAME}',
    'username' => '${DATABASE_USER}',
    'password' => '${DATABASE_PASSWORD}',
    'charset' => 'utf8mb4',
    'collation' => 'utf8mb4_unicode_ci',
    'prefix' => 'flarum_',
    'strict' => false,
    'engine' => NULL,
    'schema' => 'public',
    'sslmode' => 'prefer',
  ),
  'url' => 'https://${KOYEB_APP_NAME}.koyeb.app',
  'paths' => 
  array (
    'api' => 'api',
    'admin' => 'admin',
  ),
  'headers' => 
  array (
    'poweredByHeader' => true,
    'referrerPolicy' => 'same-origin',
  ),
);
EOF

    # Set correct permissions
    chown www-data:www-data config.php
    chmod 644 config.php

    echo "Flarum configuration created successfully!"

    # Test if Flarum can connect to the database
    echo "Testing Flarum database connection..."
    php -r "
    require 'vendor/autoload.php';
    \$config = require 'config.php';
    \$capsule = new Illuminate\Database\Capsule\Manager;
    \$capsule->addConnection(\$config['database']);
    \$capsule->setAsGlobal();
    \$capsule->bootEloquent();
    try {
        \$capsule->getConnection()->getPdo();
        echo 'Flarum database connection: SUCCESS\n';
    } catch (Exception \$e) {
        echo 'Flarum database connection: FAILED - ' . \$e->getMessage() . '\n';
        exit(1);
    }
    "

    # Run database migrations with verbose output
    echo "Running database migrations with verbose output..."
    php flarum migrate -v

    # If migrations succeed, create admin user
    if [ $? -eq 0 ]; then
        echo "Creating admin user..."
        php flarum user:create --admin --username "${FLARUM_ADMIN_USER}" --password "${FLARUM_ADMIN_PASSWORD}" --email "${FLARUM_ADMIN_EMAIL}"

        # Set forum title
        echo "Setting forum title..."
        php flarum settings:set forum_title "${FLARUM_TITLE}"

        echo "Flarum installation completed successfully!"
    else
        echo "Migrations failed. Check the error above."
        exit 1
    fi

else
    echo "Flarum is already installed. Skipping installation."
fi

# Execute the main Apache command
exec "$@"
