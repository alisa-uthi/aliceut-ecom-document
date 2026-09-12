# Fulfillment Lifecycle

**References:** US-S-05, US-S-05b, US-S-06, US-S-07, US-S-11, US-P-15, US-P-16, US-B-09, US-B-12  
**Email templates:** ET-02 (shipped), ET-03 (delivered), ET-04 (refunded), ET-13 (auto-refund — buyer), ET-13b (auto-refund — seller), ET-16 (cancelled by seller)  

## Key invariants

- One Fulfillment = one seller/currency group within an order; created on successful inventory reservation
- Tracking number (TRK-xxxxxxxx) assigned at Fulfillment creation — NOT at shipment; must not generate a second one on SHIPPED transition (US-S-06)
- PENDING refund restores stock; SHIPPED refund does NOT (goods already dispatched) (US-S-07)
- Auto-refund triggers when seller suspended AND fulfillment_window_days exceeded without shipment (US-P-16)
- Cancellation (US-S-11) only valid from PENDING; creates fake payment reversal + restores stock
- Post-delivery returns (DELIVERED → REFUNDED) are out of scope for V1 (BRD §3.2)

## Diagram

```mermaid
graph TD
    CHECKOUT["Checkout: seller/currency group processing"]
    NO_FULFILL["NO FULFILLMENT CREATED\nCart items remain in cart"]
    PENDING["PENDING\nInventory reserved, TRK-xxxxxxxx assigned"]
    SHIPPED["SHIPPED\nGoods dispatched"]
    DELIVERED["DELIVERED\nTerminal"]
    REFUNDED["REFUNDED\nTerminal"]
    CANCELLED["CANCELLED\nTerminal"]
    OOS_NOTE["Out of scope V1:\nDELIVERED to REFUNDED\npost-delivery returns"]

    CHECKOUT -->|Reservation fails| NO_FULFILL
    CHECKOUT -->|Reservation succeeds| PENDING
    PENDING -->|Seller marks shipped — US-S-06\nTracking number preserved, ET-02 to buyer| SHIPPED
    SHIPPED -->|Scheduler reaches ETA — US-P-15\nETA = placed_at + mock_delivery_days, ET-03 to buyer| DELIVERED
    PENDING -->|Seller full refund — US-S-07\nStock restored, ET-04 to buyer| REFUNDED
    SHIPPED -->|Seller full refund — US-S-07\nStock NOT restored goods in transit, ET-04 to buyer| REFUNDED
    PENDING -->|Seller cancels — US-S-11\nStock restored, fake reversal, ET-16 to buyer| CANCELLED
    PENDING -->|Auto-refund: seller suspended — US-P-16\nfulfillment_window_days exceeded, stock restored, ET-13 buyer + ET-13b seller| REFUNDED
    DELIVERED -.->|"❌ out of scope V1"| OOS_NOTE

    classDef terminal fill:#E4F5F0,stroke:#0C8A64,color:#0E1C2A,font-weight:600
    classDef active fill:#EEF2F6,stroke:#8494A0,color:#0E1C2A
    classDef warn fill:#FEF3CD,stroke:#C8960C,color:#0E1C2A,font-weight:600
    classDef oos fill:#F5F5F5,stroke:#CCCCCC,color:#999999,stroke-dasharray:4

    class DELIVERED,REFUNDED,CANCELLED terminal
    class PENDING,SHIPPED active
    class NO_FULFILL warn
    class OOS_NOTE oos
```
