# Cart API

**Module:** `Cart`  
**Parent:** [API Design Index](../api-design.md)  
**Source of truth:** [BRD v1.1](../../requirements/BRD.md), [ERD](../data-model-erd.md)

---

## Endpoint Index

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| `GET` | [`/cart`](#get-cart) | BUYER | Get cart with live-resolved prices |
| `POST` | [`/cart/items`](#add-item) | BUYER | Add item to cart |
| `PATCH` | [`/cart/items/:id`](#update-item-quantity) | BUYER | Update item quantity |
| `DELETE` | [`/cart/items/:id`](#remove-item) | BUYER | Remove item from cart |
| `DELETE` | [`/cart`](#clear-cart) | BUYER | Clear all cart items |
| `POST` | [`/cart/merge`](#merge-guest-cart-on-login) | BUYER | Merge guest localStorage cart on login (server qty wins on conflict) |

---

## DB Mapping

| Endpoint | Primary DB | Tables |
|----------|-----------|--------|
| `GET /cart` | Postgres | `cart.cart`, `cart.cart_item`, `catalog.offer`, `pricing.offer_price`, `inventory.stock` (price resolved live) |
| `POST /cart/items` | Postgres | `cart.cart` (upsert), `cart.cart_item` (insert/update qty), `catalog.offer` (status check), `inventory.stock` (qty check) |
| `PATCH /cart/items/:id` | Postgres | `cart.cart_item` (qty update), `inventory.stock` (qty check) |
| `DELETE /cart/items/:id` | Postgres | `cart.cart_item` (delete) |
| `DELETE /cart` | Postgres | `cart.cart_item` (delete all for cart) |
| `POST /cart/merge` | Postgres | `cart.cart`, `cart.cart_item` (upsert guest items; server qty wins on conflict) |

**Note:** Guest carts live in browser `localStorage`. `POST /cart/merge` is called on login to reconcile guest items into the server cart.

---

## Endpoints

### Get cart

```
GET /cart
Tag: Cart
Auth: BUYER
```
**Response 200**
```json
{
  "data": {
    "id": "uuid",
    "items": [{
      "id": "uuid",
      "offerId": "uuid",
      "productTitle": "string",
      "variantLabel": "string | null",
      "sellerName": "string",
      "quantity": 2,
      "effectivePrice": {
        "amount": "99.99",
        "currency": "USD",
        "displayAmount": "3440.00",
        "displayCurrency": "THB"
      },
      "availableQty": 10,
      "offerStatus": "ACTIVE | INACTIVE | REMOVED"
    }],
    "updatedAt": "ISO8601"
  }
}
```
Effective price is resolved live on GET (not cached from add-to-cart time).

**Field semantics:**
- `effectivePrice.amount` / `effectivePrice.currency` — seller's native pricing currency
- `effectivePrice.displayAmount` / `effectivePrice.displayCurrency` — buyer's display currency, sourced from `buyer.profile.preferred_currency` (from the JWT claims). Omitted when the buyer's preferred currency matches the seller's native currency, or when the FX rate is unavailable.

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtBuyerGuard
    participant A as API (NestJS)
    participant S as CartService
    participant P as Postgres

    C->>A: GET /cart
    activate A
    A->>G: validate JWT + BUYER role
    activate G
    alt token missing or expired
        G-->>A: 401 Unauthorized
        A-->>C: 401
    else roles does not contain BUYER
        G-->>A: 403 Forbidden
        A-->>C: 403
    end
    G-->>A: authorized { buyer_id }
    deactivate G
    A->>S: getCart(buyer_id)
    activate S
    S->>P: SELECT cart.cart WHERE user_id = :buyer_id
    P-->>S: cart row (lazily created if absent)
    S->>P: SELECT cart.cart_item<br/>JOIN catalog.offer<br/>JOIN pricing.offer_price (all price rows — seller's native currency)<br/>JOIN pricing.fx_rate (base=seller native, quote=buyer's preferred_currency from JWT)<br/>JOIN inventory.stock<br/>WHERE cart_id = :cart_id
    Note over S,P: Effective price resolved live — never cached from add-to-cart time. Resolution: account_type x current time x qty (LIST / SALE time-bounded / B2B_TIER min_qty). effectivePrice.currency = seller's native. displayAmount/displayCurrency populated when buyer preferred_currency != seller native and FX rate available.
    P-->>S: items with live effectivePrice (native + optional display fields), availableQty, offerStatus
    S-->>A: cart DTO (monetary amounts as strings)
    deactivate S
    A-->>C: 200 { data: { id, items[], updatedAt } }
    deactivate A
```

---

### Add item

```
POST /cart/items
Tag: Cart
Auth: BUYER
```
**Request body**
```json
{ "offerId": "uuid", "quantity": 1 }
```
**Response 201** — updated cart (`data`-wrapped)  
**Errors:** 400 invalid quantity, 404 offer not found/inactive, 422 quantity exceeds available stock

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtBuyerGuard
    participant A as API (NestJS)
    participant S as CartService
    participant P as Postgres

    C->>A: POST /cart/items<br/>{ offerId: uuid, quantity: N }
    activate A
    A->>G: validate JWT + BUYER role
    G-->>A: authorized { buyer_id }
    A->>S: addItem(buyer_id, offerId, quantity)
    activate S
    S->>P: SELECT catalog.offer WHERE id = :offerId
    alt offer not found
        P-->>S: no row
        S-->>A: NotFoundException
        A-->>C: 404 Offer not found or inactive
    else offer.status != ACTIVE
        P-->>S: offer (INACTIVE / REMOVED / FLAGGED)
        S-->>A: NotFoundException
        A-->>C: 404 Offer not found or inactive
    end
    S->>P: SELECT inventory.stock WHERE offer_id = :offerId
    Note over S,P: available_qty = on_hand_qty - reserved_qty
    alt quantity > available_qty
        P-->>S: insufficient stock
        S-->>A: InsufficientStockException
        A-->>C: 422 Quantity exceeds available stock
    end
    S->>P: INSERT INTO cart.cart (user_id)<br/>ON CONFLICT (user_id) DO NOTHING RETURNING id
    Note over S,P: Ensures exactly one server cart row per buyer
    S->>P: INSERT INTO cart.cart_item (cart_id, offer_id, quantity)<br/>ON CONFLICT (cart_id, offer_id)<br/>DO UPDATE SET quantity = :quantity, updated_at = now()
    P-->>S: upserted cart_item
    S->>P: SELECT full cart (live price resolution — same as GET /cart)
    P-->>S: cart DTO
    S-->>A: cart DTO
    deactivate S
    A-->>C: 201 { data: { updated cart } }
    deactivate A
```

---

### Update item quantity

```
PATCH /cart/items/:cartItemId
Tag: Cart
Auth: BUYER
```
**Request body**
```json
{ "quantity": 3 }
```
**Response 200** — updated cart item (`data`-wrapped)  
**Errors:** 400, 404, 422

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtBuyerGuard
    participant A as API (NestJS)
    participant S as CartService
    participant P as Postgres

    C->>A: PATCH /cart/items/:cartItemId<br/>{ quantity: N }
    activate A
    A->>G: validate JWT + BUYER role
    G-->>A: authorized { buyer_id }
    A->>S: updateItemQty(buyer_id, cartItemId, quantity)
    activate S
    S->>P: SELECT cart.cart_item<br/>JOIN cart.cart ON cart.id = cart_item.cart_id<br/>WHERE cart_item.id = :cartItemId AND cart.user_id = :buyer_id
    alt item not found or owned by different buyer
        P-->>S: no row
        S-->>A: NotFoundException
        A-->>C: 404 Cart item not found
    end
    P-->>S: cart_item row (offer_id)
    S->>P: SELECT inventory.stock WHERE offer_id = :offer_id
    alt quantity > available_qty
        P-->>S: insufficient stock
        S-->>A: InsufficientStockException
        A-->>C: 422 Quantity exceeds available stock
    end
    S->>P: UPDATE cart.cart_item<br/>SET quantity = :quantity, updated_at = now()<br/>WHERE id = :cartItemId
    P-->>S: updated row
    S-->>A: updated cart item DTO (amounts as strings)
    deactivate S
    A-->>C: 200 { data: { updated cart item } }
    deactivate A
```

---

### Remove item

```
DELETE /cart/items/:cartItemId
Tag: Cart
Auth: BUYER
```
**Response 204**

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtBuyerGuard
    participant A as API (NestJS)
    participant S as CartService
    participant P as Postgres

    C->>A: DELETE /cart/items/:cartItemId
    activate A
    A->>G: validate JWT + BUYER role
    G-->>A: authorized { buyer_id }
    A->>S: removeItem(buyer_id, cartItemId)
    activate S
    S->>P: SELECT cart.cart_item<br/>JOIN cart.cart ON cart.id = cart_item.cart_id<br/>WHERE cart_item.id = :cartItemId AND cart.user_id = :buyer_id
    alt not found or owned by different buyer
        P-->>S: no row
        S-->>A: NotFoundException
        A-->>C: 404 Not Found
    end
    S->>P: DELETE FROM cart.cart_item WHERE id = :cartItemId
    P-->>S: deleted
    deactivate S
    A-->>C: 204 No Content
    deactivate A
```

---

### Clear cart

```
DELETE /cart
Tag: Cart
Auth: BUYER
```
**Response 204**

#### Sequence

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtBuyerGuard
    participant A as API (NestJS)
    participant S as CartService
    participant P as Postgres

    C->>A: DELETE /cart
    activate A
    A->>G: validate JWT + BUYER role
    G-->>A: authorized { buyer_id }
    A->>S: clearCart(buyer_id)
    activate S
    S->>P: SELECT cart.cart WHERE user_id = :buyer_id
    P-->>S: cart_id
    S->>P: DELETE FROM cart.cart_item WHERE cart_id = :cart_id
    P-->>S: N rows deleted (0 if already empty)
    deactivate S
    A-->>C: 204 No Content
    deactivate A
```

---

### Merge guest cart (on login)

```
POST /cart/merge
Tag: Cart
Auth: BUYER
```
**Request body**
```json
{
  "guestItems": [
    { "offerId": "uuid", "quantity": 1 }
  ]
}
```
Merges guest cart items into the authenticated cart. Duplicate offers: server-side cart quantity is kept (not summed).  
**Response 200** — merged cart (`data`-wrapped)

#### Sequence

**Conflict resolution rule (server qty wins):**
- Guest item whose `offerId` already exists in the server cart: server quantity is kept unchanged; guest quantity is silently discarded.
- Guest item whose `offerId` is absent from the server cart: offer status and available stock are checked live at merge time; item is inserted capped at `available_qty`. Inactive or unavailable offers are silently skipped.

```mermaid
sequenceDiagram
    participant C as Client
    participant G as JwtBuyerGuard
    participant A as API (NestJS)
    participant S as CartService
    participant P as Postgres

    C->>A: POST /cart/merge<br/>{ guestItems: [{ offerId, quantity }] }
    Note over C,A: Called right after login/register when localStorage guest cart is non-empty
    activate A
    A->>G: validate JWT + BUYER role
    G-->>A: authorized { buyer_id }
    A->>S: mergeGuestCart(buyer_id, guestItems)
    activate S
    S->>P: INSERT INTO cart.cart (user_id)<br/>ON CONFLICT (user_id) DO NOTHING RETURNING id
    P-->>S: cart_id (created if first login)
    S->>P: SELECT cart.cart_item WHERE cart_id = :cart_id
    P-->>S: existing server items (offer_id -> quantity map)

    loop for each guestItem in guestItems
        S->>P: SELECT catalog.offer<br/>WHERE id = :offerId AND status = 'ACTIVE'
        alt offer is INACTIVE, REMOVED, or FLAGGED
            P-->>S: no active row
            Note over S: Skip — offer unavailable#59; no insert, no error
        else offer is ACTIVE
            P-->>S: offer row
            alt offerId already in server cart
                Note over S: Server qty wins — no INSERT or UPDATE. Guest quantity discarded.
            else offerId not in server cart
                S->>P: SELECT inventory.stock WHERE offer_id = :offerId
                P-->>S: available_qty (checked live at merge time)
                Note over S: cappedQty = MIN(guestItem.quantity, available_qty)
                opt cappedQty > 0
                    S->>P: INSERT INTO cart.cart_item<br/>(cart_id, offer_id, cappedQty)
                end
            end
        end
    end

    S->>P: SELECT cart.cart_item<br/>JOIN catalog.offer<br/>JOIN pricing.offer_price (seller's native currency — live resolution)<br/>JOIN pricing.fx_rate (base=seller native, quote=buyer preferred_currency from JWT)<br/>JOIN inventory.stock<br/>WHERE cart_id = :cart_id
    P-->>S: merged cart with live prices (native + optional display fields)
    S-->>A: merged cart DTO
    deactivate S
    A-->>C: 200 { data: { merged cart } }
    deactivate A
```
