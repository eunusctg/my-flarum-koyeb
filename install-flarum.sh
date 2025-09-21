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
        --dbdriver "pgsql"

    echo "Flarum installation completed successfully!"

    # Configure R2 if environment variables are set
    if [ -n "${R2_ACCESS_KEY_ID}" ] && [ -n "${R2_SECRET_ACCESS_KEY}" ] && [ -n "${R2_BUCKET}" ]; then
        echo "Configuring Cloudflare R2 storage..."

        # Use a PHP script to safely modify the config.php file
        php <<EOF
<?php
\$config = include 'config.php';

// Define the R2 filesystem disk configuration
\$r2Config = [
    'driver' => 's3',
    'region' => 'auto',
    'bucket' => '${R2_BUCKET}',
    'url' => 'https://pub-${R2_ACCOUNT_ID}.r2.dev/${R2_BUCKET}',
    'endpoint' => 'https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com',
    'use_path_style_endpoint' => true,
    'key' => '${R2_ACCESS_KEY_ID}',
    'secret' => '${R2_SECRET_ACCESS_KEY}',
    'visibility' => 'public',
    'root' => 'assets'
];

// Merge the new configuration
\$config['filesystems'] = [
    'disks' => [
        'flarum-uploads' => \$r2Config,
        'flarum-assets' => \$r2Config
    ]
];

// Write the updated configuration back to the file
file_put_contents('config.php', '<?php return ' . var_export(\$config, true) . ';');
echo "R2 configuration applied successfully.\n";
?>
EOF

        echo "Cloudflare R2 configuration completed!"
    else
        echo "R2 environment variables not set. Skipping R2 configuration."
    fi

else
    echo "Flarum is already installed. Skipping installation."
fi

# Execute the main Apache command
exec "$@"
