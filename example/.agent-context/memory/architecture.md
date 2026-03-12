# Architecture

Shopware is a modular monolith with domain-first organization. Four core domains in `src/Core/`, plus Admin SPA and Storefront.

**Non-obvious details:**
- DAL is NOT Doctrine — completely custom, optimized for e-commerce read patterns
- Entity Indexer pattern: write-time pre-computation for fast reads (don't aggregate in read paths)
- Parent-Child inheritance: variant products inherit all fields from parent unless overridden
- Translation fallback chain: current language → parent language → system default language
- CMS resolvers can be either static (pass-through) or dynamic (data-fetching)
