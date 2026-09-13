# Epic: FE-ADMIN — Admin Portal

**Epic ID:** FE-ADMIN  
**Sprint(s):** 18  
**Total Tasks:** 9  

## Epic Goal

Admin portal (separate Angular app at `admin-app`): KYC review queue, listing moderation queue, seller search and profile view, suspend/reinstate modals, admin dashboard. Admin role only; BUYER/SELLER routes blocked. All admin actions write to `admin.action` audit log via backend.

---

## Tasks

### FE-ADMIN-001 — Admin dashboard

- **US Ref:** US-A-01
- **Estimate:** M
- **Dependencies:** FE-SHARED-001, FE-SHARED-002
- **Spec References:** `phase-1/technical-design/api-design/admin.md`

**Implementation Notes:**
- Route: `/dashboard` (admin-app root; requires `adminGuard`)
- Summary cards (from `GET /admin/dashboard`):
  - Pending KYC submissions
  - Flagged listings awaiting review
  - Active sellers count
  - Suspended sellers count
- Recent activity: last 10 admin actions from `GET /admin/actions?limit=10`
- Each action row: action type, target (seller name or listing title), admin user, timestamp
- Quick-action buttons: "Review KYC", "Review listings"

**Done Criteria:**
- Dashboard accessible only with ADMIN role; others redirected to login
- Summary card counts are real-time (fetched on load)
- Recent actions table shows formatted timestamps

---

### FE-ADMIN-002 — KYC review queue

- **US Ref:** US-A-02
- **Estimate:** M
- **Dependencies:** FE-ADMIN-001
- **Spec References:** `phase-1/technical-design/api-design/admin.md`

**Implementation Notes:**
- Route: `/kyc`
- Calls `GET /admin/kyc?status=UNDER_REVIEW&limit=20&cursor=`
- Table: business name, submitted-at date, document count, status badge, "Review" button
- Status filter: UNDER_REVIEW / APPROVED / REJECTED (default: UNDER_REVIEW)
- Sort: submitted-at ascending (oldest first — FIFO review queue)
- Cursor-based "load more"

**Done Criteria:**
- Queue shows UNDER_REVIEW submissions oldest-first
- Status filter updates results
- "Review" button navigates to `/kyc/:sellerId`
- Empty state when no pending submissions

---

### FE-ADMIN-003 — KYC review page

- **US Ref:** US-A-03
- **Estimate:** L
- **Dependencies:** FE-ADMIN-002
- **Spec References:** `phase-1/technical-design/api-design/admin.md`

**Implementation Notes:**
- Route: `/kyc/:sellerId`
- Calls `GET /admin/sellers/:sellerId` + `GET /seller/kyc/documents/:sellerId`
- Sections:
  - Seller info: business name, registration number, tax ID, contact
  - Documents: each document shown with type label + "View document" button
  - Document viewer: opens KYC doc from MinIO in new tab (pre-signed URL from `GET /admin/kyc/documents/:docId/url`)
- Action buttons:
  - "Approve": `POST /admin/kyc/:sellerId/approve` → confirm dialog → success snackbar + redirect to queue
  - "Reject": dialog with required rejection reason text input → `POST /admin/kyc/:sellerId/reject { reason }` → redirect to queue
- KYC doc access logged by backend (NFR-09); no client-side logging needed

**Done Criteria:**
- All documents linked to MinIO pre-signed URLs (not stored in browser)
- Approve: seller status changes to APPROVED; email notification triggered (backend event)
- Reject: rejection reason required; cannot reject without reason
- After action: redirected back to KYC queue; processed item removed from UNDER_REVIEW filter

---

### FE-ADMIN-004 — Flagged listings queue

- **US Ref:** US-A-04
- **Estimate:** M
- **Dependencies:** FE-ADMIN-001
- **Spec References:** `phase-1/technical-design/api-design/admin.md`

**Implementation Notes:**
- Route: `/moderation`
- Calls `GET /admin/moderation?status=FLAGGED&limit=20&cursor=`
- Table: product title, seller name, flagged-at date, flag reason, "Review" button
- Status filter: FLAGGED / REMOVED / CLEARED (default: FLAGGED)
- Sort: flagged-at ascending (oldest-first)

**Done Criteria:**
- Queue shows FLAGGED listings oldest-first
- "Review" navigates to `/moderation/:offerId`
- Empty state when no flagged listings

---

### FE-ADMIN-005 — Listing moderation actions

- **US Ref:** US-A-05
- **Estimate:** L
- **Dependencies:** FE-ADMIN-004
- **Spec References:** `phase-1/technical-design/api-design/admin.md`

**Implementation Notes:**
- Route: `/moderation/:offerId`
- Calls `GET /catalog/offers/:offerId` + `GET /catalog/products/:productId`
- Shows: product title, description, images, seller name, flag reason, current listing status
- Actions:
  - "Remove listing": confirm dialog + required reason → `POST /admin/moderation/listings/:offerId/remove { reason }`
  - "Clear flag" (if false positive): `POST /admin/moderation/listings/:offerId/clear`
- After action: return to moderation queue; listing removed from FLAGGED filter

**Done Criteria:**
- Full product details visible including images
- Remove requires reason (cannot submit empty)
- Clear: listing restored to ACTIVE in buyer search within ES event lag (~5s)
- Both actions recorded in `admin_action` audit table (via backend)

---

### FE-ADMIN-006 — Seller search

- **US Ref:** US-A-06
- **Estimate:** M
- **Dependencies:** FE-ADMIN-001
- **Spec References:** `phase-1/technical-design/api-design/admin.md`

**Implementation Notes:**
- Route: `/sellers`
- Search input: `GET /admin/sellers?search=&status=&limit=20&cursor=`
- Table: seller name, email, KYC status badge, seller status badge, registered-at date, "View" button
- Status filter: seller_status: ACTIVE / SUSPENDED / INACTIVE
- KYC status filter: APPROVED / UNDER_REVIEW / REJECTED
- Search by: seller name, business name, email (handled backend-side)

**Done Criteria:**
- Search by email finds exact match
- Status filters combinable
- "View" navigates to `/sellers/:sellerId`
- Empty search returns all sellers (paginated)

---

### FE-ADMIN-007 — Seller profile view

- **US Ref:** US-A-07
- **Estimate:** M
- **Dependencies:** FE-ADMIN-006
- **Spec References:** `phase-1/technical-design/api-design/admin.md`

**Implementation Notes:**
- Route: `/sellers/:sellerId`
- Calls `GET /admin/sellers/:sellerId`
- Sections:
  - Account info: name, email, registered-at, roles
  - Seller profile: business name, KYC status, seller status
  - Recent admin actions on this seller (from `GET /admin/actions?targetId=:sellerId&limit=5`)
  - Quick stats: active listings count, total orders
- Action buttons based on current status:
  - ACTIVE seller: "Suspend" button
  - SUSPENDED seller: "Reinstate" button
  - KYC UNDER_REVIEW: "Review KYC" button → `/kyc/:sellerId`

**Done Criteria:**
- All seller data displayed correctly
- Recent actions show correct admin usernames and timestamps
- Correct action buttons visible based on current status

---

### FE-ADMIN-008 — Suspend modal

- **US Ref:** US-A-08
- **Estimate:** M
- **Dependencies:** FE-ADMIN-007
- **Spec References:** `phase-1/technical-design/api-design/admin.md`

**Implementation Notes:**
- MatDialog component: `SuspendSellerDialogComponent`
- Opened from seller profile page "Suspend" button
- Fields:
  - Reason: text area (required; min 10 chars)
  - Duration: radio buttons — Permanent / Temporary
  - Temporary: days input (1–365; shown only when Temporary selected)
- Submit: `POST /admin/sellers/:sellerId/suspend { reason, duration_days? }`
- On success: dialog closes; seller profile status badge updates to SUSPENDED; snackbar
- On error: error message inside dialog; dialog stays open

**Done Criteria:**
- Reason required; submit disabled without it
- Duration field visible only for temporary suspension
- After suspend: profile page shows SUSPENDED badge; "Suspend" button replaced by "Reinstate"
- Kafka `seller.suspended` event triggers refund of open fulfillments and ES index update (backend handles; no frontend action needed)

---

### FE-ADMIN-009 — Reinstate modal

- **US Ref:** US-A-09
- **Estimate:** S
- **Dependencies:** FE-ADMIN-007
- **Spec References:** `phase-1/technical-design/api-design/admin.md`

**Implementation Notes:**
- MatDialog component: `ReinstateSellerDialogComponent`
- Opened from seller profile page "Reinstate" button
- Fields:
  - Optional note (text area; not required)
- Submit: `POST /admin/sellers/:sellerId/reinstate { note? }`
- On success: dialog closes; seller profile status badge updates to ACTIVE; snackbar
- On error: error message inside dialog

**Done Criteria:**
- Can reinstate without note (note optional)
- After reinstate: profile page shows ACTIVE badge; "Reinstate" button replaced by "Suspend"
- Seller receives reinstatement email (backend notification via Kafka event)
- Admin action logged in `admin_action` table (backend)
