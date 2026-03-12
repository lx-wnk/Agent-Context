# Architecture Decisions

## Custom DAL over Doctrine ORM

Shopware uses a purpose-built Data Abstraction Layer instead of Doctrine. Rationale: e-commerce requires heavily optimized read paths with pre-computed aggregations (Entity Indexer pattern). Doctrine's unit-of-work and lazy-loading patterns don't align with this.

## Domain-First Module Organization

Code is grouped by business domain (`Content`, `Checkout`) rather than technical layer (`Controller`, `Model`). Each domain owns its entities, services, and routes.

## Meteor Component Library (Admin)

Admin UI uses the Meteor component library (Shopware's Vue.js design system) instead of raw Vue components. All new admin UI must use Meteor components for consistency.
