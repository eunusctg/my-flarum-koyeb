# Use the latest stable PHP-Apache image
FROM php:apache

# Install system dependencies
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y \
        libpng-dev \
        libjpeg-dev \
        libfreetype6-dev \
        libzip-dev \
        zip \
        unzip \
        git \
        curl \
        wget \
        sqlite3 \
        libsqlite3-dev \
        libonig-dev \
        libxml2-dev \
        libpq-dev \
        postgresql-client && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configure and install only essential PHP extensions
RUN docker-php-ext-configure gd --with-freetype --with-jpeg && \
    docker-php-ext-install \
        bcmath \
        gd \
        mbstring \
        opcache \
        pdo \
        pdo_mysql \
        pdo_pgsql \
        pdo_sqlite \
        zip

# Enable Apache's rewrite module
RUN a2enmod rewrite

# Install latest Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Copy configuration files
COPY ./apache-flarum.conf /etc/apache2/sites-available/000-default.conf
COPY ./install-flarum.sh /usr/local/bin/install-flarum.sh

# Set the working directory
WORKDIR /var/www/html

# Create Flarum project using Composer
RUN composer create-project flarum/flarum . --stability=beta --no-interaction

# Set permissions
RUN chown -R www-data:www-data /var/www/html && \
    chmod -R 755 /var/www/html/storage && \
    chmod +x /usr/local/bin/install-flarum.sh

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/install-flarum.sh"]
CMD ["apache2-foreground"]
