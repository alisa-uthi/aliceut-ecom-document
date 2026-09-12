# Seller Account Lifecycle

**References:** US-S-00, US-S-01, US-S-02, US-A-01, US-A-02, US-A-05, US-A-05b, US-P-18  
**Email templates:** ET-06 (KYC approved), ET-07 (KYC rejected), ET-10 (suspended), ET-11 (auto-reinstated), ET-12 (admin reinstated), ET-14 (KYC received — to seller), ET-21 (KYC alert — to admin)  

## Key invariants

- Seller registration at `/seller/register` — no buyer account required; existing buyer accounts can link SELLER role via same form (must authenticate with password; OAuth-only buyers set password first via US-B-15)
- KYC submit fires ET-14 to seller AND ET-21 to admin; ET-21 includes SLA deadline (submitted_at + 72 hours / 3 calendar days); applies to resubmissions too
- Suspension deactivates all listings; seller retains read-only access to PENDING orders for fulfillment only (US-A-05)
- On reinstatement: only listings deactivated by the suspension are restored; independently-removed listings remain REMOVED (US-A-05b)
- Timed suspensions (7/30/90 days) auto-lift via scheduler (US-P-18); listings reactivated automatically + ET-11 to seller
- Permanent suspension requires explicit admin confirmation dialog; no auto-lift path

## Diagram

```mermaid
graph TD
    S0([ ]) --> UNREGISTERED

    UNREGISTERED["UNREGISTERED\nVisitor, no account"]
    REGISTERED["REGISTERED\nSeller account created or linked\nat /seller/register"]
    KYC_PENDING["KYC_PENDING\nApplication submitted\nAdmin review SLA: 3 days"]
    KYC_REJECTED["KYC_REJECTED\nRejected — update docs and resubmit"]
    ACTIVE["ACTIVE\nApproved — can list products and fulfill orders"]
    SUSPENDED["SUSPENDED\nListings deactivated\n7d / 30d / 90d / permanent\nRead-only pending orders access retained for shipment"]
    SUSP_EXP["SUSPENSION_EXPIRED\nTimed TTL elapsed\nAwaiting scheduler auto-lift"]

    UNREGISTERED -->|"Create account or link existing buyer\nat /seller/register — email/password"| REGISTERED
    REGISTERED -->|"Submit KYC application\nET-14 to seller, ET-21 to admin"| KYC_PENDING
    KYC_PENDING -->|Admin approves — ET-06| ACTIVE
    KYC_PENDING -->|Admin rejects with reason — ET-07| KYC_REJECTED
    KYC_REJECTED -->|"Update docs + resubmit\nET-14 to seller, ET-21 to admin"| KYC_PENDING
    ACTIVE -->|Admin suspends with reason + duration — ET-10| SUSPENDED
    SUSPENDED -->|Timed TTL expires| SUSP_EXP
    SUSP_EXP -->|Scheduler auto-lifts US-P-18 — ET-11, listings restored| ACTIVE
    SUSPENDED -->|Admin lifts early US-A-05b — ET-12, listings restored| ACTIVE

    classDef stateActive fill:#E4F5F0,stroke:#0C8A64,color:#0E1C2A,font-weight:600
    classDef stateSuspended fill:#FEF3CD,stroke:#C8960C,color:#0E1C2A,font-weight:600
    classDef stateRejected fill:#FEE8E8,stroke:#C0392B,color:#0E1C2A,font-weight:600
    classDef stateNeutral fill:#EEF2F6,stroke:#8494A0,color:#0E1C2A
    classDef stateStart fill:#0C8A64,stroke:#0C8A64,color:#FFF

    class ACTIVE stateActive
    class SUSPENDED,SUSP_EXP stateSuspended
    class KYC_REJECTED stateRejected
    class UNREGISTERED,REGISTERED,KYC_PENDING stateNeutral
    class S0 stateStart
```
