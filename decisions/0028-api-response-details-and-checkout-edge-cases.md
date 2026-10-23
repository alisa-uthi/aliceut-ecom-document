# ADR-0028: API response details, checkout edge cases and V1 limitations the design left open

**Status:** Accepted  
**Date:** 2026-10-22  
**Affects:** `phase-1/technical-design/api-design/catalog.md`, `pricing.md`, `cart.md`, `orders.md`, `seller.md`, `search.md`; `phase-1/requirements/user-stories/email-templates.md` (ET-01 logo)  
**Implemented by:** none needed; the built behaviour is the decision (`spec-compliance.md` entry 1)  

## Context

Entry 1 of `spec-compliance.md` listed behaviours the design never stated and the code settled by construction: the `GET /catalog/categories/:categoryId` body, an unknown `categoryId` filter, the FX-rates error table, several checkout edge cases, the KYC submit/resubmit overlap left by ADR-0021, the order e-mail logo link, search facet currencies, catalog offer rules, the KYC read, and order detail details. The owner authorized applying defaults: take the option closest to what is built and least disruptive. Each was checked against the backend before being written down.

## Decision

1. **Category detail** returns the category with its direct children only; each child has `children: []`. Unknown id is `404`. The public tree includes prohibited categories.
2. **Unknown `categoryId` on `GET /catalog/products`** is an empty page, not an error.
3. **`GET /pricing/fx-rates`**: `400` for a `base` outside the seller-allowed currencies; a valid base with no rows is `200` with `rates: []`. No `404`/`422`.
4. **Checkout**: a missing FX row for a line fails the whole request `422` (never a fallback rate in an immutable snapshot); a `cartItems` id not in the caller's cart is `404`; groups, totals and reservation count `ACTIVE` lines only. The cart returns `effectivePrice: null` / `lineTotal: null` for a line with no live `LIST` row and excludes it from totals; it reads `seller.seller_profile.business_name` for `sellerName` (now in the cart DB mapping).
5. **Skipped lines and failed groups are not on `GET /orders/:id`.** V1 limitation, documented, not built: the confirmation page shows them only from the checkout response, and they remain in the cart.
6. **`POST /seller/kyc/resubmit`** is kept as a documented alias of `POST /seller/kyc` for a rejected seller (one code path, ADR-0021). Not deprecated in V1; the frontend uses `POST /seller/kyc`.
7. **Order e-mail logo link** is a documented dev-only limitation in V1: signed for `MINIO_PUBLIC_ENDPOINT`, valid 7 days. V2 needs a real public origin.
8. **Search facets**: `priceRange.min`/`max` are USD; `displayMin`/`displayMax` are the requested currency.
9. **Catalog offers**: an offer without a live `LIST` row is omitted; an invalid Bearer token is anonymous; the sale window is `starts_at <= now() < ends_at`; offers order by offer id.
10. **Seller KYC read**: `priorRejectionReason` is the reason on the application the latest one supersedes; a seller with no profile gets the same `404` as one with no application.
11. **Order detail**: `shippingAddress.phone` is always null in V1 (no phone column); `itemCount` is the sum of line quantities; `DELIVERED` is removed from the `orderStatus` enum (all delivered is `COMPLETED`) and stays valid on `fulfillment.status`.
12. **`search.md` `category_path` rationale** is corrected: the path travels in the event because a consumer's inputs are its payload and its own document (consumer-field-matrix.md section 1), not because the indexer could not read `catalog.*`.

## Consequences

The specs now describe the built behaviour and each item is a recorded decision rather than a silent mismatch. The `DELIVERED` removal narrows the documented enum; the backend `ORDER_STATUSES` in `libs/orders/src/http/dto/list-orders.query.dto.ts` and the order response DTO still list `DELIVERED` and should drop it so the generated OpenAPI matches (small follow-up, not done here). Reloading the order confirmation loses skipped lines and failed groups until a later phase persists them. E-mail logos do not work outside a developer machine until V2.

## Alternatives considered

Persist skipped/failed records and return them on `GET /orders/:id` (rejected: new table, outside the default). Deprecate `/resubmit` (rejected: breaks existing clients for no gain). Fall back to the last known FX rate at checkout (rejected: puts an unverified rate into an immutable snapshot). Make an unknown `categoryId` a `404` (rejected: changes built behaviour; clients already treat empty as empty).
