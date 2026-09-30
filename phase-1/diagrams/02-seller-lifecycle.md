# Seller Account Lifecycle

**References:** US-S-00, US-S-01, US-S-02, US-A-01, US-A-02, US-A-05, US-A-05b, US-P-18  
**Email templates:** ET-06 (KYC approved), ET-07 (KYC rejected), ET-10 (suspended), ET-11 (auto-reinstated), ET-12 (admin reinstated), ET-14 (KYC received — to seller), ET-21 (KYC alert — to admin)  

## Key invariants

- Seller registration at `/seller/register` — no buyer account required; existing buyer accounts can link SELLER role via same form (must authenticate with password; OAuth-only buyers set password first via US-B-15)
- KYC submit fires ET-14 to seller AND ET-21 to admin; ET-21 includes SLA deadline (`kyc_application.review_due_at` — 3 business days, BRD §12 #14); applies to resubmissions too
- Suspension deactivates all listings; seller retains read-only access to PENDING orders for fulfillment only (US-A-05)
- On reinstatement: only listings deactivated by the suspension are restored; independently-removed listings remain REMOVED (US-A-05b)
- Timed suspensions (7/30/90 days) auto-lift via scheduler (US-P-18); listings reactivated automatically + ET-11 to seller
- Permanent suspension requires explicit admin confirmation dialog; no auto-lift path
- The lifecycle below spans **two independent columns**, not one status field: `seller.seller_profile.kyc_status` (`PENDING_KYC`, `APPROVED`, `REJECTED`) and `seller.seller_profile.suspension_status` (`ACTIVE`, `SUSPENDED`). A suspended seller is still KYC-approved — suspension never moves `kyc_status`, and approval never moves `suspension_status`. `SUSPENSION_EXPIRED` is not a stored value: it is the derived condition `suspension_status = SUSPENDED AND suspended_until < now()`, which the US-P-18 scheduler polls and clears.

## Diagram

```mermaid
graph TD
    S0([ ]) --> UNREGISTERED

    UNREGISTERED["UNREGISTERED\nVisitor, no account\nNo seller_profile row exists"]
    REGISTERED["REGISTERED\nSeller account created or linked\nat /seller/register"]
    K_PENDING["kyc_status = PENDING_KYC\nApplication submitted\nAdmin review SLA: 3 days"]
    K_REJECTED["kyc_status = REJECTED\nRejected — update docs and resubmit"]
    S_ACTIVE["kyc_status = APPROVED\nsuspension_status = ACTIVE\nCan list products and fulfill orders"]
    S_SUSPENDED["suspension_status = SUSPENDED\nkyc_status stays APPROVED\nListings deactivated\n7d / 30d / 90d / permanent\nRead-only pending orders access retained for shipment"]
    S_EXPIRED["Derived: SUSPENSION_EXPIRED\nsuspended_until < now()\nAwaiting scheduler auto-lift\nNot a stored enum value"]

    UNREGISTERED -->|"Create account or link existing buyer\nat /seller/register — email/password"| REGISTERED
    REGISTERED -->|"Submit KYC application\nET-14 to seller, ET-21 to admin"| K_PENDING
    K_PENDING -->|Admin approves — ET-06| S_ACTIVE
    K_PENDING -->|Admin rejects with reason — ET-07| K_REJECTED
    K_REJECTED -->|"Update docs + resubmit\nET-14 to seller, ET-21 to admin"| K_PENDING
    S_ACTIVE -->|Admin suspends with reason + duration — ET-10| S_SUSPENDED
    S_SUSPENDED -->|Timed suspended_until elapses| S_EXPIRED
    S_EXPIRED -->|Scheduler auto-lifts US-P-18 — ET-11, listings restored| S_ACTIVE
    S_SUSPENDED -->|Admin lifts early US-A-05b — ET-12, listings restored| S_ACTIVE

    classDef stateActive fill:#E4F5F0,stroke:#0C8A64,color:#0E1C2A,font-weight:600
    classDef stateSuspended fill:#FEF3CD,stroke:#C8960C,color:#0E1C2A,font-weight:600
    classDef stateRejected fill:#FEE8E8,stroke:#C0392B,color:#0E1C2A,font-weight:600
    classDef stateNeutral fill:#EEF2F6,stroke:#8494A0,color:#0E1C2A
    classDef stateStart fill:#0C8A64,stroke:#0C8A64,color:#FFF

    class S_ACTIVE stateActive
    class S_SUSPENDED,S_EXPIRED stateSuspended
    class K_REJECTED stateRejected
    class UNREGISTERED,REGISTERED,K_PENDING stateNeutral
    class S0 stateStart
```
