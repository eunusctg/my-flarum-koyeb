# Use the latest stable PHP-Apache image
FROM php:apache

# Install system dependencies and all necessary PHP extensions
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
        libpq-dev && \  # Critical: Added for PostgreSQL support
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configure and install PHP extensions (Added pdo_pgsql for PostgreSQL)
RUN docker-php-ext-configure gd --with-freetype --with-jpeg && \
    docker-php-ext-configure zip && \
    docker-php-ext-install \
        bcmath \
        ctype \
        curl \
        dom \
        fileinfo \
        gd \
        iconv \
        intl \
        mbstring \
        opcache \
        pdo \
        pdo_mysql \
        pdo_pgsql \  # Required for your Koyeb database
        pdo_sqlite \
        session \
        simplexml \
        sqlite3 \
        tokenizer \
        xml \
        xmlwriter \
        zip

# Enable Apache's rewrite module for Flarum's clean URLs
RUN a2enmod rewrite

# Install latest Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Copy our custom Apache configuration and installation script
COPY ./apache-flarum.conf /etc/apache2/sites-available/000-default.conf
COPY ./install-flarum.sh /usr/local/bin/install-flarum.sh

# Set the working directory to the web root
WORKDIR /var/www/html

# Download and extract the latest Flarum release
RUN curl -o flarum.tar.gz -SL "https://flarum.org/releases/flarum-latest.tar.gz" && \
    tar -xzf flarum.tar.gz -C /var/www/html/ --strip-components=1 && \
    rm flarum.tar.gz

# Install PHP dependencies via Composer
RUN composer install --no-dev -o --prefer-dist --no-interaction

# Set correct permissions for the web server and make our script executable
RUN chown -R www-data:www-data /var/www/html && \
    chmod -R 755 /var/www/html/storage && \
    chmod +x /usr/local/bin/install-flarum.sh

# Set the entrypoint to run our installation script and then start Apache
ENTRYPOINT ["/usr/local/bin/install-flarum.sh"]
CMD ["apache2-foreground"]
