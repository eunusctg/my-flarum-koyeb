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

    # Test basic database operations to ensure connectivity works
    echo "Testing basic database operations..."
    php << 'EOF'
<?php
require 'vendor/autoload.php';

$config = require 'config.php';

$capsule = new Illuminate\Database\Capsule\Manager;
$capsule->addConnection($config['database']);
$capsule->setAsGlobal();
$capsule->bootEloquent();

try {
    // Test simple query
    $result = $capsule->getConnection()->select('SELECT version() as version');
    echo "PostgreSQL version: " . $result[0]->version . "\n";
    
    // Test creating a simple table
    $capsule->getConnection()->statement('CREATE TABLE IF NOT EXISTS test_migration (id SERIAL PRIMARY KEY, name VARCHAR(255))');
    echo "Test table created successfully!\n";
    
    // Test inserting data
    $capsule->getConnection()->statement("INSERT INTO test_migration (name) VALUES ('test')");
    echo "Test data inserted successfully!\n";
    
    // Test reading data
    $results = $capsule->getConnection()->select('SELECT * FROM test_migration');
    echo "Test data read successfully! Found " . count($results) . " rows.\n";
    
    // Test dropping the table
    $capsule->getConnection()->statement('DROP TABLE IF EXISTS test_migration');
    echo "Test table dropped successfully!\n";
    
    exit(0);
} catch (Exception $e) {
    echo "Database operation failed: " . $e->getMessage() . "\n";
    echo "File: " . $e->getFile() . ":" . $e->getLine() . "\n";
    exit(1);
}
?>
EOF

    DB_TEST_EXIT_CODE=$?
    
    if [ $DB_TEST_EXIT_CODE -eq 0 ]; then
        echo "Database operations test successful!"
        
        # Now try to run Flarum migrations with error output
        echo "Running Flarum migrations..."
        echo "=========================================="
        # Use a PHP script to run migrations with better error handling
        php << 'EOF'
<?php
require 'vendor/autoload.php';

// Load Flarum application
$app = require 'vendor/flarum/core/src/Install/Console/Application.php';

// Set up the migrate command
$input = new Symfony\Component\Console\Input\ArrayInput([
    'command' => 'migrate',
    '--force' => true,
]);

$output = new Symfony\Component\Console\Output\StreamOutput(fopen('php://stdout', 'w'));

try {
    $exitCode = $app->run($input, $output);
    exit($exitCode);
} catch (Exception $e) {
    echo "Migration error: " . $e->getMessage() . "\n";
    echo "File: " . $e->getFile() . ":" . $e->getLine() . "\n";
    exit(1);
}
?>
EOF

        MIGRATION_EXIT_CODE=$?
        echo "=========================================="
        echo "Migration exit code: $MIGRATION_EXIT_CODE"

        if [ $MIGRATION_EXIT_CODE -eq 0 ]; then
            echo "Migrations successful!"
            
            echo "Creating admin user..."
            php flarum user:create --admin --username "${FLARUM_ADMIN_USER}" --password "${FLARUM_ADMIN_PASSWORD}" --email "${FLARUM_ADMIN_EMAIL}"

            echo "Setting forum title..."
            php flarum settings:set forum_title "${FLARUM_TITLE}"

            echo "Flarum installation completed successfully!"

            # Configure R2 if environment variables are set
            if [ -n "${R2_ACCESS_KEY_ID}" ] && [ -n "${R2_SECRET_ACCESS_KEY}" ] && [ -n "${R2_BUCKET}" ]; then
                echo "Configuring Cloudflare R2 storage..."

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
            echo "Migrations failed with exit code: $MIGRATION_EXIT_CODE"
            exit 1
        fi

    else
        echo "Database operations test failed with exit code: $DB_TEST_EXIT_CODE"
        exit 1
    fi

else
    echo "Flarum is already installed. Skipping installation."
fi

# Execute the main Apache command
exec "$@"
