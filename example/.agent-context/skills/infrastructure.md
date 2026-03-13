---
name: infrastructure
description: Docker setup, CI pipeline, Composer scripts, build and QA commands
triggers:
  - docker
  - ci
  - composer
  - build
  - phpstan
  - phpunit
  - php-cs-fixer
  - pipeline
  - eslint
  - stylelint
---

# Infrastructure — Full Reference

## Development Setup

```bash
composer install                    # Install PHP dependencies
npm install --prefix src/Storefront  # Install storefront dependencies
npm install --prefix src/Administration  # Install admin dependencies
docker compose up -d               # Start services (MySQL, Elasticsearch, Redis)
bin/console system:install --create-database  # Initial setup
```

## Building

```bash
composer run build                  # Full build (admin + storefront + assets)
bin/build-storefront.sh             # Build storefront only
bin/build-administration.sh         # Build administration only
bin/console theme:compile           # Compile theme (SCSS → CSS)
```

## Frontend Development

```bash
bin/watch-storefront.sh             # Watch storefront with hot reload
bin/watch-administration.sh         # Watch admin SPA with hot reload (port 8080)
```

## Quality Assurance

```bash
composer run check                  # Full QA pipeline (PHPStan + CS-Fixer + PHPUnit)
composer run phpstan                # Static analysis
composer run cs-fix                 # Fix code style
composer run phpunit                # Unit + integration tests
npm run lint                        # ESLint + Stylelint (frontend)
```

## CI Pipeline (GitHub Actions)

Runs in parallel on every PR:

1. `phpstan` — Static analysis
2. `php-cs-fixer` — PHP code style
3. `phpunit` — Unit tests
4. `integration-tests` — Integration tests (MySQL service container)
5. `eslint` — JavaScript linting
6. `stylelint` — SCSS/CSS linting
7. `build` — Full build verification

## Docker Services

| Service       | Port | Purpose           |
| ------------- | ---- | ----------------- |
| MySQL 8.0     | 3306 | Database          |
| Elasticsearch | 9200 | Product search    |
| Redis         | 6379 | Cache + sessions  |
| Mailhog       | 8025 | Email testing     |

## Useful Console Commands

```bash
bin/console cache:clear                          # Clear all caches
bin/console plugin:install --activate MyPlugin   # Install + activate plugin
bin/console dal:refresh:index                    # Re-run all entity indexers
bin/console messenger:consume async              # Process async messages
bin/console scheduled-task:run                   # Run scheduled tasks
```
