# Layer 1 — Project Bootstrap

## Tech Stack

- **PHP:** >=8.2 on Symfony 7
- **Database:** MySQL 8.0+ or MariaDB 10.11+
- **ORM:** None — custom Data Abstraction Layer (DAL), not Doctrine
- **Admin:** Vue.js 3 SPA (Meteor component library)
- **Storefront:** Twig + Bootstrap 5 + Vanilla JS (plugin system)
- **Build:** Composer (PHP), npm + Webpack (assets)
- **CI:** GitHub Actions with composite actions

## Core Domains

| Domain | Path | Responsibility |
|--------|------|---------------|
| Framework | `src/Core/Framework/` | DAL, bundle system, plugin API, migrations |
| System | `src/Core/System/` | Configuration, users, locales, number ranges |
| Content | `src/Core/Content/` | Products, categories, CMS, media, SEO |
| Checkout | `src/Core/Checkout/` | Cart, orders, customers, payment, shipping |
| Admin | `src/Administration/` | Vue.js admin SPA |
| Storefront | `src/Storefront/` | Twig templates, controllers, theme system |
