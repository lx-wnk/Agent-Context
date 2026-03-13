# Infrastructure

Full reference available in `.agent-context/skills/infrastructure.md`.

**Quick facts:**
- Build: `composer run build` (full), `bin/build-storefront.sh`, `bin/build-administration.sh`
- QA: `composer run check` (PHPStan + CS-Fixer + PHPUnit)
- CI: GitHub Actions — runs PHPStan, CS-Fixer, PHPUnit, ESLint, Stylelint in parallel
- Docker: `docker compose up -d` — MySQL on 3306, Elasticsearch on 9200, Admin on 8080
