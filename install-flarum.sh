#!/bin/bash
set -e

cd /var/www/html

# Check if Flarum is already installed (if config.php exists)
if [ ! -f config.php ]; then
    echo "Flarum not found. Starting automatic installation..."

    # Run the Flarum install command using environment variables
    php flarum install --file \
        --admin-user "${FLARUM_ADMIN_USER}" \
        --admin-password "${FLARUM_ADMIN_PASSWORD}" \
        --admin-email "${FLARUM_ADMIN_EMAIL}" \
        --title "${FLARUM_TITLE}" \
        --dbhost "${DATABASE_HOST}" \
        --dbname "${DATABASE_NAME}" \
        --dbuser "${DATABASE_USER}" \
        --dbpass "${DATABASE_PASSWORD}" \
        --dbdriver "pgsql" # Use 'pgsql' driver for PostgreSQL

    echo "Flarum installation completed successfully!"
else
    echo "Flarum is already installed. Skipping installation."
fi

# Execute the main Apache command (from the CMD directive)
exec "$@"
