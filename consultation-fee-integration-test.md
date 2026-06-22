# Bahmni ↔ Odoo Billing Integration — Test Guide

This document covers both directions of the billing integration:

- **Part A — Bahmni → Odoo:** Consultation fee sync triggered when a patient is saved on registration page 2.
- **Part B — Odoo → Bahmni:** Billing order receipt endpoint that Odoo calls to push payment status back into Bahmni.

---

## Part A — Bahmni → Odoo (Consultation Fee Sync)

### End-to-End Workflow

```
Save button (Bahmni registration page 2)
  └─▶ visitController.js  submit() → save() → submitFeeToOdoo()
        └─▶ popup: "Synchronizing Patient with Billing System..." (attemptSync)
              └─▶ POST /openmrs/ws/rest/v1/odooconnector/consultation-fee
                    └─▶ ConsultationFeeController  (validate fields)
                          └─▶ ConsultationFeeOdooService  (up to maxRetries+1 attempts, backoff between)
                                ├─▶ POST .../web/session/authenticate  (JSON-RPC → session_id from Set-Cookie)
                                └─▶ POST .../api/bdsec/sales  (sale order payload + Cookie: session_id)
        ┌────────────────────────────────────────────────────────────────────────────┐
        │ success            → popup: "Consultation Order Sent to Billing"            │
        │ errorType=patient_sync_failed → popup: "Patient Sync Failed" + Retry/OK      │
        │ errorType=order_failed        → popup: "Consultation Order Failed" + Retry/OK│
        └────────────────────────────────────────────────────────────────────────────┘
              Retry → attemptSync() again (no re-save of the encounter)
```

---

## 1. Odoo Endpoints & Authentication

### Authentication

**URL:** `https://bdsec.grace-erp-consultancy.com/web/session/authenticate`
**Method:** POST  
**Content-Type:** application/json

```json
{
  "jsonrpc": "2.0",
  "method": "call",
  "params": {
    "db": "odoo",
    "login": "emrsync",
    "password": "Admin123"
  }
}
```

**Successful auth response (excerpt):**
```json
{
  "jsonrpc": "2.0",
  "id": null,
  "result": {
    "uid": 12,
    "session_id": "abc123def456...",
    "username": "emrsync",
    "db": "odoo"
  }
}
```

The `session_id` from `result.session_id` is stored and sent as `Cookie: session_id=<value>` on the sales call.

---

### Sales Endpoint

**URL:** `https://bdsec.grace-erp-consultancy.com/api/bdsec/sales`  
**Method:** POST  
**Content-Type:** application/json  
**Cookie:** `session_id=<value from auth>`

---

## 2. OpenMRS Global Properties

Set these in **Administration → Manage Global Properties** (or via SQL provisioning):

| Property | Value | Description |
|---|---|---|
| `odooconnector.odooUrl` | `https://bdsec.grace-erp-consultancy.com` | Odoo base URL — no trailing slash |
| `odooconnector.odooDb` | `odoo` | Odoo database name |
| `odooconnector.odooLogin` | `emrsync` | Service-account login |
| `odooconnector.odooPassword` | `Admin123` | Service-account password |
| `odooconnector.consultation.odooPath` | `/api/bdsec/sales` | Sales endpoint path |
| `odooconnector.consultation.shopId` | `1` | Odoo POS shop ID for consultations |
| `odooconnector.consultation.connectTimeoutSeconds` | `15` | Max seconds to wait for the TCP/TLS connection to Odoo to establish |
| `odooconnector.consultation.readTimeoutSeconds` | `30` | Max seconds to wait for Odoo's response once a request has been sent |
| `odooconnector.consultation.maxRetries` | `2` | Automatic retries (in addition to the first attempt) on connection-level failures only |
| `odooconnector.consultation.retryBackoffMillis` | `1500` | Base backoff delay (ms) before each retry, multiplied by the attempt number |

To change the Odoo server URL without touching code:

**Via Admin UI:** Administration → Manage Global Properties → search `odooconnector`

**Via SQL:**
```sql
UPDATE global_property SET property_value = 'https://bdsec.grace-erp-consultancy.com'
WHERE property = 'odooconnector.odooUrl';

UPDATE global_property SET property_value = '/api/bdsec/sales'
WHERE property = 'odooconnector.consultation.odooPath';
```

---

## 3. Payload Sent to Odoo (`/api/bdsec/sales`)

Field names must match exactly (Odoo is case-sensitive):

```json
{
  "patient_unique_id": "ABC200023",
  "patientUuid": "3b6a5e2a-1234-4b9c-a832-000000000001",
  "shop_id": 1,
  "Payment_method": "free",
  "Payment_type": "CBHI",
  "VisitUuid": "9f3d0c11-abcd-4321-bcde-000000000002",
  "voided": false,
  "dateCreated": "2026-05-21T08:30:00.000Z",
  "dateChanged": "2026-05-21T08:30:00.000Z",
  "createdBy": "nurse.jane",
  "lines": [
    {
      "default_code": "consultation",
      "quantity": 1
    }
  ]
}
```

**Field mapping from Bahmni registration form:**

| Frontend concept / source | Payload field | Notes |
|---|---|---|
| Patient primary identifier | `patient_unique_id` | e.g. `ABC200023` |
| Patient UUID | `patientUuid` | OpenMRS UUID |
| GP `odooconnector.consultation.shopId` | `shop_id` | Integer, default 1 |
| Obs concept "Payment Method" | `Payment_method` | Capital P — free text, Odoo accepts any value |
| Obs concept "Mode of Payment" | `Payment_type` | Capital P — **validated by Odoo, see table below** |
| Visit UUID | `VisitUuid` | Capital V |
| Always `false` on registration save | `voided` | |
| `new Date().toISOString()` | `dateCreated` | |
| `new Date().toISOString()` | `dateChanged` | |
| `$rootScope.currentUser.username` | `createdBy` | |
| Hardcoded | `lines[0].default_code` | Always `"consultation"` |
| Hardcoded | `lines[0].quantity` | Always `1` |

**Confirmed valid `Payment_type` values (live-tested 2026-05-22):**

| Value | Accepted by Odoo | Notes |
|---|---|---|
| `CBHI` | ✅ Yes | Case-insensitive |
| `cbhi` | ✅ Yes | |
| `cash` | ✅ Yes | |
| `insurance` | ✅ Yes | |
| `free` | ❌ No | Returns "Failed to create sale order" |
| `OOP` / `oop` | ❌ No | Not a valid Odoo selection value |
| `private` | ❌ No | |

**Important:** The OpenMRS "Mode of Payment" concept answer names must exactly match one of the valid Odoo values above (`CBHI`, `cash`, or `insurance`). If the concept answers use different names, they will fail silently on the Bahmni side and the Odoo record will not be created.

**`Payment_method`** is a free-text field in Odoo — any string value is accepted (`free`, `cash`, `insurance`, `waiver`, `mobile`, etc.).

---

## 4. Sample Payloads

### Standard cash patient

```json
{
  "patient_unique_id": "ABC200023",
  "patientUuid": "3b6a5e2a-1234-4b9c-a832-000000000001",
  "shop_id": 1,
  "Payment_method": "cash",
  "Payment_type": "OOP",
  "VisitUuid": "9f3d0c11-abcd-4321-bcde-000000000002",
  "voided": false,
  "dateCreated": "2026-05-21T08:30:00.000Z",
  "dateChanged": "2026-05-21T08:30:00.000Z",
  "createdBy": "nurse.jane",
  "lines": [{"default_code": "consultation", "quantity": 1}]
}
```

### CBHI (insurance) patient

```json
{
  "patient_unique_id": "ABC200099",
  "patientUuid": "3b6a5e2a-1234-4b9c-a832-000000000099",
  "shop_id": 1,
  "Payment_method": "free",
  "Payment_type": "CBHI",
  "VisitUuid": "9f3d0c11-abcd-4321-bcde-000000000099",
  "voided": false,
  "dateCreated": "2026-05-21T09:15:00.000Z",
  "dateChanged": "2026-05-21T09:15:00.000Z",
  "createdBy": "clerk.john",
  "lines": [{"default_code": "consultation", "quantity": 1}]
}
```

---

## 5. Expected Responses

Every response now includes `patientSynced` (boolean). Failure responses additionally include
`errorType`, set to either `"patient_sync_failed"` or `"order_failed"` — see
§10 Patient-Sync vs. Order Classification for exactly
how that's decided. The encounter save itself is **never blocked** by any of these outcomes.

### Success

```json
{
  "status": "success",
  "message": "Sale order created successfully.",
  "sale_order_id": 76,
  "sale_order_name": "S00076",
  "patient_id": 36,
  "patient_name": "Abebe Alemu Ale",
  "bahmni_patient_id": "ABC200023",
  "patient_unique_id": "ABC200023",
  "shop_id": 1,
  "shop_name": "Pharmacy",
  "payment_type": "cbhi",
  "is_cbhi_patient": true,
  "is_insurance_customer": false,
  "state": "draft",
  "warnings": [],
  "patientSynced": true
}
```

### Patient sync failed — Odoo unreachable after retries (live-tested 2026-06-17)

Encounter is still saved — non-fatal. `odooconnector.odooUrl` was pointed at an unreachable host;
3 attempts (1 initial + 2 retries, 1.5s then 3s backoff) were made before giving up:

```json
{
  "status": "error",
  "errorType": "patient_sync_failed",
  "patientSynced": false,
  "message": "Unable to reach the billing system (Odoo) to synchronize the patient record after 3 attempt(s): unreachable.invalid.test-domain-bahmni-2",
  "patientUuid": "5d2216ac-00a7-460e-9bd6-a3f0ea97fbc4",
  "VisitUuid": "bf625a64-7a01-4e64-bda1-1e299a345a9e"
}
```

### Order failed — Odoo rejected the sale order (live-tested 2026-06-17)

Triggered with `Payment_type: "free"` (an invalid Odoo selection value — see §3 table). Odoo's
`/api/bdsec/sales` returns `{status, error, details}` with **no patient fields at all** even though
the patient may already exist as an Odoo customer — so this is classified as `order_failed`, not
`patient_sync_failed`, and Odoo's own error text is surfaced verbatim:

```json
{
  "odooResponseCode": 500,
  "status": "error",
  "error": "Failed to create sale order.",
  "details": "Wrong value for sale.order.payment_type: 'free'",
  "patientSynced": false,
  "errorType": "order_failed",
  "message": "Failed to create sale order. Wrong value for sale.order.payment_type: 'free'",
  "patientUuid": "79de723b-50e3-4e90-9e91-adf8bae73a26",
  "VisitUuid": "292e8fb2-5e02-4776-bff4-63799870e8ae"
}
```

### Order failed — patient synced, sale order missing from response

```json
{
  "status": "error",
  "errorType": "order_failed",
  "patientSynced": true,
  "patient_id": 36,
  "patient_name": "Abebe Alemu Ale",
  "message": "Patient synchronized, but the consultation order could not be created.",
  "patientUuid": "3b6a5e2a-1234-4b9c-a832-000000000001",
  "VisitUuid": "9f3d0c11-abcd-4321-bcde-000000000002"
}
```

### Validation failure — missing required field

Unreachable from the real UI (the frontend already guards on `patientUuid`/`visitUuid` before
calling this endpoint); kept for completeness when testing the controller directly:

```json
{
  "status": "rejected",
  "error": "patientUuid is required"
}
```

---

## 6. Manual curl Test Scripts

### Step 1: Get an OpenMRS session cookie

```bash
curl -s -c /tmp/omrs.txt \
  -X POST "http://localhost:8080/openmrs/ws/rest/v1/session" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"Admin123"}'
```

### Step 2: Post a consultation payload (replace UUIDs)

```bash
curl -v -b /tmp/omrs.txt \
  -X POST "http://localhost:8080/openmrs/ws/rest/v1/odooconnector/consultation-fee" \
  -H "Content-Type: application/json" \
  -d '{
    "patientId":       "ABC200023",
    "patientUuid":     "REPLACE-WITH-REAL-PATIENT-UUID",
    "currentVisitUuid":"REPLACE-WITH-REAL-VISIT-UUID",
    "paymentMethod":   "free",
    "modeOfPayment":   "CBHI",
    "voided":          false,
    "dateCreated":     "2026-05-21T08:30:00.000Z",
    "dateChanged":     "2026-05-21T08:30:00.000Z",
    "createdBy":       "admin"
  }'
```

**Expected response:** Odoo sale order JSON with `sale_order_id` and `sale_order_name`.

### Step 3: Test validation rejection

```bash
curl -v -b /tmp/omrs.txt \
  -X POST "http://localhost:8080/openmrs/ws/rest/v1/odooconnector/consultation-fee" \
  -H "Content-Type: application/json" \
  -d '{"currentVisitUuid":"some-uuid"}'
# Expected: {"status":"rejected","error":"patientUuid is required"}
```

### Step 4: Test Odoo auth directly

```bash
curl -v \
  -X POST "https://bdsec.grace-erp-consultancy.com/web/session/authenticate" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "call",
    "params": {"db":"odoo","login":"emrsync","password":"Admin123"}
  }'
# Expected: result.session_id present in response
```

### Step 5: Test Odoo sales endpoint directly (after getting session_id from Step 4)

```bash
SESSION_ID="paste-session-id-here"

curl -v \
  -X POST "https://bdsec.grace-erp-consultancy.com/api/bdsec/sales" \
  -H "Content-Type: application/json" \
  -H "Cookie: session_id=${SESSION_ID}" \
  -d '{
    "patient_unique_id": "ABC200023",
    "patientUuid":       "3b6a5e2a-1234-4b9c-a832-000000000001",
    "shop_id":           1,
    "Payment_method":    "free",
    "Payment_type":      "CBHI",
    "VisitUuid":         "9f3d0c11-abcd-4321-bcde-000000000002",
    "voided":            false,
    "dateCreated":       "2026-05-21T08:30:00.000Z",
    "dateChanged":       "2026-05-21T08:30:00.000Z",
    "createdBy":         "nurse.jane",
    "lines":             [{"default_code":"consultation","quantity":1}]
  }'
# Expected: {"status":"success","sale_order_id":...,"sale_order_name":"S000..."}
```

### Step 6: Simulate patient-sync failure (Odoo unreachable) and verify retry

```bash
# 1. Point odooUrl at an unreachable host via the systemsetting REST resource
#    (a raw SQL UPDATE will NOT work — OpenMRS caches global properties in memory
#    and only reloads them when set through AdministrationService/REST)
GP_UUID=$(curl -sk -b /tmp/omrs.txt \
  "https://localhost/openmrs/ws/rest/v1/systemsetting?q=odooconnector.odooUrl" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['results'][0]['uuid'])")

curl -sk -b /tmp/omrs.txt -X POST "https://localhost/openmrs/ws/rest/v1/systemsetting/${GP_UUID}" \
  -H "Content-Type: application/json" \
  -d '{"value":"https://unreachable.invalid.test-domain"}'

# 2. Post a consultation payload — expect ~9s elapsed (3 attempts: 0s, +1.5s, +3s backoff)
curl -v -b /tmp/omrs.txt \
  -X POST "https://localhost/openmrs/ws/rest/v1/odooconnector/consultation-fee" \
  -H "Content-Type: application/json" \
  -d '{"patientId":"ABC200023","patientUuid":"REPLACE-WITH-REAL-PATIENT-UUID",
       "currentVisitUuid":"REPLACE-WITH-REAL-VISIT-UUID","paymentMethod":"cash","modeOfPayment":"cash"}'
# Expected: {"status":"error","errorType":"patient_sync_failed","patientSynced":false,
#            "message":"Unable to reach the billing system (Odoo) ... after 3 attempt(s): ..."}

# 3. Restore the real URL
curl -sk -b /tmp/omrs.txt -X POST "https://localhost/openmrs/ws/rest/v1/systemsetting/${GP_UUID}" \
  -H "Content-Type: application/json" \
  -d '{"value":"https://bdsec.grace-erp-consultancy.com"}'

# 4. Re-post the same payload (this is what clicking "Retry" in the popup does) — expect success
```

### Step 7: Trigger an order-level rejection (patient may already be synced, order is not)

```bash
curl -v -b /tmp/omrs.txt \
  -X POST "https://localhost/openmrs/ws/rest/v1/odooconnector/consultation-fee" \
  -H "Content-Type: application/json" \
  -d '{"patientId":"ABC200023","patientUuid":"REPLACE-WITH-REAL-PATIENT-UUID",
       "currentVisitUuid":"REPLACE-WITH-REAL-VISIT-UUID","paymentMethod":"free","modeOfPayment":"free"}'
# Expected: {"status":"error","errorType":"order_failed","patientSynced":false,
#            "error":"Failed to create sale order.","details":"Wrong value for sale.order.payment_type: 'free'",
#            "message":"Failed to create sale order. Wrong value for sale.order.payment_type: 'free'"}
```

---

## 7. OpenMRS Log Verification

When a consultation is saved successfully, `openmrs.log` should contain these lines in order:

```
INFO  ConsultationFeeController - [ConsultationFee] Received payload from Bahmni registration: {...}
INFO  ConsultationFeeController - [ConsultationFee] Validation passed — forwarding to Odoo patientId=ABC200023 ...
INFO  ConsultationFeeOdooService - [ConsultationFee] Preparing Odoo payload — endpoint=https://bdsec.grace-erp-consultancy.com/api/bdsec/sales ...
INFO  ConsultationFeeOdooService - [ConsultationFee] Authenticating with Odoo — url=https://bdsec.grace-erp-consultancy.com/web/session/authenticate ...
INFO  ConsultationFeeOdooService - [ConsultationFee] Auth response — HTTP 200 body: {...}
INFO  ConsultationFeeOdooService - [ConsultationFee] Authentication succeeded — session_id obtained
INFO  ConsultationFeeOdooService - [ConsultationFee] Payload to Odoo: {"patient_unique_id":"ABC200023",...}
INFO  ConsultationFeeOdooService - [ConsultationFee] Odoo sales response — HTTP 200 body: {...}
INFO  ConsultationFeeOdooService - [ConsultationFee] Sale order created successfully — sale_order_id=76 sale_order_name=S00076 patient_name=...
```

On a connection-level failure, each attempt and the final outcome are logged (live capture,
2026-06-17 — note the ~1.5s then ~3s gaps matching `retryBackoffMillis × attempt`):
```
WARN  ConsultationFeeOdooService - [ConsultationFee] Attempt 1 failed for patientUuid=... — unreachable...: Name or service not known — retrying after backoff
WARN  ConsultationFeeOdooService - [ConsultationFee] Attempt 2 failed for patientUuid=... — unreachable... — retrying after backoff
WARN  ConsultationFeeOdooService - [ConsultationFee] Attempt 3 failed for patientUuid=... — unreachable... — giving up
ERROR ConsultationFeeOdooService - [ConsultationFee] Patient sync to Odoo FAILED after 3 attempt(s) for patientUuid=... — encounter already saved, payload not forwarded: ...
```

On an order-level rejection (patient may or may not be synced; Odoo returned a structured error):
```
WARN  ConsultationFeeOdooService - [ConsultationFee] Odoo rejected the ORDER (structured error, patient status unknown) — patientId=... patientUuid=... httpCode=500 message=Failed to create sale order. ...
```

On a genuine patient-sync rejection (Odoo's response had no patient fields and no structured error):
```
WARN  ConsultationFeeOdooService - [ConsultationFee] Patient sync FAILED — patientId=... patientUuid=... httpCode=...
```

---

## 8. End-to-End Test Checklist

- [ ] Register a new patient (page 1: name, DOB, gender, patient ID)
- [ ] On page 2 fill: Payment Method (`free` or `cash`), Mode of Payment (`CBHI`/`cash`/`insurance`)
- [ ] Click **Save**
- [ ] Popup immediately shows the loading state: "Synchronizing Patient with Billing System..."
- [ ] Browser console shows: `[ConsultationFee] Preparing to sync — patientId: ABC2XXXXX`
- [ ] Popup turns to "Consultation Order Sent to Billing" (success) showing Status/Message/Patient Name
- [ ] `openmrs.log` shows auth succeeded and sale order created
- [ ] Odoo back-office shows a new draft sale order (S000XX) for the patient
- [ ] Simulate Odoo unreachable (systemsetting REST call, see §6 Step 6): popup shows
      **"Patient Sync Failed"** with the specific reachability message and a **Retry** button —
      it must NOT say anything about a generic billing/order error
- [ ] Restore the real Odoo URL, click **Retry** in the popup: registration is NOT re-submitted
      (no new encounter created), only the sync re-attempts, and it succeeds
- [ ] Trigger an order-level rejection (Mode of Payment = `free`, see §6 Step 7): popup shows
      **"Consultation Order Failed"** with Odoo's actual validation message (e.g. "Wrong value for
      sale.order.payment_type: 'free'"), not a generic patient-sync message
- [ ] Test with missing `patientUuid` in payload: controller returns `{"status":"rejected",...}`

---

## 9. Implementation Notes (Part A)

- `default_code` is always `"consultation"` — hardcoded in `ConsultationFeeOdooService.buildSalesPayloadJson()`. Odoo resolves the product price from this code.
- `quantity` is always `1` — hardcoded alongside `default_code`.
- `shop_id` comes from the `odooconnector.consultation.shopId` global property (integer, default `1`).
- The Bahmni encounter save is **never blocked** by Odoo failures. If Odoo is down, the service retries (see §10) and ultimately returns `status: "error", errorType: "patient_sync_failed"` — the encounter itself is already saved regardless.
- Session authentication is performed fresh on every request. Odoo sessions are short-lived; caching was deliberately not added to avoid stale-session bugs.
- `Mode of Payment` concept answers are automatically lowercased before sending (`"Cash"` → `"cash"`) to satisfy Odoo's case-sensitive Payment_type validation.
- The sync fires on every Save regardless of whether a "Consultation Fee" observation exists — Odoo determines the price from the `consultation` product code.

---

## 10. Patient-Sync vs. Order Classification, Retry & Timeout Behavior

`/api/bdsec/sales` does two things in one call — finds/creates the Odoo customer ("patient sync")
and creates the sale order ("billing"). Its response shape is the only signal available to
distinguish which part failed, so `ConsultationFeeOdooService.postSalesOrder()` classifies it like
this (in order):

1. **Connection-level failure** (DNS, refused connection, connect-phase timeout) before any data
   reached Odoo → retried automatically (see §2 GP table: `maxRetries`, `retryBackoffMillis`),
   then `errorType: "patient_sync_failed"`.
2. Response contains `patient_id` / `patient_name` / `bahmni_patient_id` **and** `sale_order_id` /
   `sale_order_name` **and** HTTP was successful → success.
3. Response contains patient fields but **no** sale fields → `errorType: "order_failed"` (patient
   confirmed synced, order step failed).
4. Response has no patient fields but **does** contain `status` or `error`/`details` → Odoo's
   application code ran and explicitly rejected the order (e.g. invalid `Payment_type`) →
   `errorType: "order_failed"`, with Odoo's own `error`/`details` text surfaced as the message.
   **Confirmed empirically (2026-06-17): Odoo's `/api/bdsec/sales` does not echo back any
   patient_* fields on this kind of rejection, even though the customer record may already exist.**
   Treating it as `patient_sync_failed` would have been misleading and non-actionable (retrying
   with the same bad value fails identically every time).
5. Anything else (unparseable body, no recognizable fields at all) → conservative default,
   `errorType: "patient_sync_failed"`.

**What gets auto-retried and what doesn't:** only connection-level failures (`UnknownHostException`,
`ConnectException`, or any `IOException` whose message contains "connect") are retried — these
happen before any data reaches Odoo, so retrying is always safe. A read-timeout on the sales call
itself is **not** auto-retried, because Odoo may have already created the sale order and a blind
retry could create a duplicate (`/api/bdsec/sales` has no idempotency key, unlike the inbound
`billing/orders` endpoint — see Part B). This is the same business risk a clerk re-clicking Save
already carries today.

**Frontend Retry button:** on any `errorType` (or a total `$http` failure reaching our own
controller), `visitController.js` shows a popup with **Retry** and **OK**. Retry re-POSTs the same
payload — the encounter is already saved at this point, so nothing about registration is re-run.
OK gives up and lets the user continue; the billing desk can reconcile manually. No silent
client-side auto-retry was added on top of the backend's own retry loop — the single `$http` call
already legitimately takes longer (up to `connectTimeoutSeconds × (maxRetries+1)` in the worst
case) instead of failing fast, which is what avoids flashing "Error" while sync is still genuinely
in progress.

---

## 11. Auto-Replication into `odoo_billing_payment_status` (PENDING)

As soon as `ConsultationFeeOdooService.postSalesOrder()` classifies the Odoo response as a full
success (patient synced **and** sale order created, see §10 step 2), it now also replicates that
same response into `odoo_billing_payment_status` with `payment_status=PENDING`, via the exact same
persistence path Part B's inbound `billing/orders` endpoint uses (`BillingOrderService`) — so the
payment gate (`BillingPaymentGateInterceptor`, the Patient Queue gate in Part C, and
`/odoo/billing/is-paid`) has a row to find immediately, instead of waiting for Odoo to
asynchronously push the real payment confirmation back later via Part B.

- **Trigger:** only the full-success branch in `postSalesOrder()` — `errorType=patient_sync_failed`
  and `errorType=order_failed` responses are never replicated, since there is no real sale order to
  record yet.
- **Mapping:** `sale_id` ← Odoo's `sale_order_id`, `sale_name` ← `sale_order_name`, `patient_id` ←
  the Bahmni `patient_unique_id` already in scope, `patient_uuid`/`visit_uuid` ← the same values
  sent to Odoo, `customer_type` ← Odoo's `payment_type` if present, `services` ← a single
  `Consultation` entry (matching the hardcoded `default_code` sent to Odoo). `amountDue`/
  `amountPaid`/`currency` are left to `BillingOrderService`'s own defaults (`0.00`/`0.00`/`ETB`),
  since Odoo's `/api/bdsec/sales` response carries no price information.
- **New internal entry point:** `BillingOrderService.processBillingOrder(Map<String, Object> body)`
  — an overload of the existing `processBillingOrder(body, httpResponse)` for callers with no
  `HttpServletResponse` (i.e. not an inbound HTTP request from Odoo). Validation/error paths behave
  identically; they just have no HTTP status code to set.
- **Failure isolation:** the replication call is wrapped in try/catch — any failure is logged as a
  WARN and swallowed. It can never change the `consultation-fee` response already being returned to
  the Bahmni frontend, consistent with the rest of this service's non-fatal design (§9).
- **Idempotency / future PAID push:** the row is keyed on `(sale_id, payment_status)` exactly as in
  Part B. When Odoo later pushes the real payment confirmation through `billing/orders` with
  `payment_status=paid` (or `waived`), that is a status **transition** for the same `sale_id`, not a
  duplicate — it is persisted as a brand-new history row per §9, and the gate's
  `ORDER BY odooSyncTimestamp DESC LIMIT 1` picks up the newer PAID/WAIVED row automatically. The
  PENDING row is never overwritten in place.

**Live-tested (2026-06-18):** new patient `BDSEC200028` (uuid
`ad4ed236-ce0e-4c2e-a01d-0e309bdc96dd`), visit uuid `6fd5663e-df0b-4cee-8c47-4a088428b532`, posted to
`/odooconnector/consultation-fee` with `paymentMethod=cash`, `modeOfPayment=cash`:

```json
{
  "status": "success",
  "sale_order_id": 172,
  "sale_order_name": "S00186",
  "patient_name": "Claude TestPatient",
  "bahmni_patient_id": "BDSEC200028",
  "patientSynced": true
}
```

Resulting row in `odoo_billing_payment_status`:

```
id=29 patient_id=BDSEC200028 visit_id=42 service_type=CONSULTATION
service_reference_id=172 odoo_invoice_id=S00186 payment_status=PENDING
amount_paid=0.00 amount_due=0.00 currency=ETB
```

`GET /odoo/billing/is-paid?patientUuid=ad4ed236-...&visitUuid=6fd5663e-...&serviceType=CONSULTATION`
immediately afterward → `{"paid":false,"patientId":"BDSEC200028","visitId":42,"serviceType":"CONSULTATION"}`
— confirming the gate sees the PENDING row right away and continues to block until Odoo separately
pushes a `paid`/`waived` status through Part B's endpoint.

---

## Part B — Odoo → Bahmni (Billing Order Receipt)

### End-to-End Workflow

```
Odoo (after payment confirmed)
  └─▶ POST /openmrs/ws/rest/v1/odooconnector/billing/orders
        Authorization: Bearer <token>   (or x-api-key: <key>)
              └─▶ BillingOrderController  (authenticate — 401 if invalid)
                    └─▶ BillingOrderService
                          ├─▶ Idempotency check via sale_id  (return early if already stored)
                          ├─▶ Resolve patient_uuid → OpenMRS patient integer ID  (400 if unknown)
                          ├─▶ Resolve visit_uuid   → OpenMRS visit integer ID    (400 if unknown)
                          ├─▶ Fan out services[]   → one odoo_billing_payment_status row per item
                          └─▶ Return { status, message, external_sale_id, internal_billing_id, processed_at }
```

---

### 1. Endpoint Reference

| Item | Value |
|------|-------|
| **Method** | `POST` |
| **URL** | `https://localhost/openmrs/ws/rest/v1/odooconnector/billing/orders` |
| **Content-Type** | `application/json` |
| **Auth header** | `Authorization: Bearer <token>` *(preferred)* |
| **Alt auth header** | `x-api-key: <key>` |
| **Success status** | HTTP 200 |
| **Auth failure** | HTTP 401 |
| **Validation failure** | HTTP 400 |

---

### 2. Configuration (Required Before First Use)

#### 2a. OpenMRS Global Properties

Navigate to **Administration → Manage Global Properties** and search `odooconnector.billing`:

| Property | Default | Purpose |
|----------|---------|---------|
| `odooconnector.billing.inboundBearerToken` | `test-token-123` | Shared secret Odoo sends in `Authorization: Bearer`. **Must be changed in production.** |
| `odooconnector.billing.inboundApiKey` | *(blank)* | Alternative shared secret sent in `x-api-key`. Leave blank to disable this auth method. |

**Change the token via SQL (recommended for automation):**
```sql
UPDATE global_property
SET property_value = 'your-strong-secret-here'
WHERE property = 'odooconnector.billing.inboundBearerToken';
```

**Change via Admin UI:** Administration → Manage Global Properties → search `inboundBearerToken` → update value → Save.

> **Important:** After updating Global Properties the change takes effect immediately — no OpenMRS restart required.

#### 2b. Optional — Nginx Proxy

The OpenMRS REST path is `/openmrs/ws/rest/v1/odooconnector/billing/orders`.  
To expose it at the shorter URL `/api/billing/orders`, add to the Bahmni nginx config:

```nginx
location /api/billing/ {
    proxy_pass http://openmrs:8080/openmrs/ws/rest/v1/odooconnector/billing/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

#### 2c. Supported `payment_status` Values

| Value sent by Odoo | Stored as | Gate result |
|--------------------|-----------|-------------|
| `paid` | `PAID` | ✅ Patient allowed through |
| `waived` | `WAIVED` | ✅ Patient allowed through |
| `pending` | `PENDING` | ❌ Gate blocks patient |
| `cancelled` | `CANCELLED` | ❌ Gate blocks patient |

#### 2d. Supported `services[].serviceType` Values

| Value (case-insensitive) | Stored as |
|--------------------------|-----------|
| `Consultation` | `CONSULTATION` |
| `Lab_Order` | `LAB_ORDER` |
| `Medication` | `MEDICATION` |
| `Procedure` | `PROCEDURE` |
| `Radiology` | `RADIOLOGY` |
| `Bed` | `BED` |
| `Dental` | `DENTAL` |

---

### 3. Payload Schema

All fields and their behaviour:

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `sale_id` | integer | **Yes** | Odoo sale order ID — idempotency key together with `payment_status` (see §9) |
| `sale_name` | string | No | e.g. `"S00042"` — stored as `odoo_invoice_id` |
| `patient_name` | string | No | Informational — not stored |
| `patient_id` | string | No | Bahmni identifier e.g. `"BDSEC200010"` — cross-checked against the identifier resolved from `patient_uuid`; **never used directly for persistence**. A numeric value here is ignored with a WARN log (see §9) |
| `patient_uuid` | string (UUID) | **Yes** | Resolved to a `Patient`; its **preferred identifier string** (e.g. `"BDSEC200024"`) is what gets stored as `patient_id` — never the numeric database ID |
| `visit_uuid` | string (UUID) | **Yes** | Resolved to OpenMRS visit integer ID |
| `amountDue` | number | No | Remaining balance — default `0.00` |
| `amountPaid` | number | No | Amount paid — default `0.00` |
| `currency` | string | No | ISO currency code — default `"ETB"` |
| `payment_status` | string | No | `paid`, `waived`, `pending`, `cancelled` — default `"PENDING"` |
| `payment_date` | string | No | `yyyy-MM-dd` or `yyyy-MM-dd'T'HH:mm:ss'Z'` |
| `customer_type` | string | No | `cash`, `cbhi`, `insurance` — logged only, not stored |
| `services` | array | No | One record created per item; defaults to `[{serviceType:"CONSULTATION"}]` if omitted |
| `services[].serviceType` | string | No | See supported values above |
| `services[].price_unit` | number | No | Informational — not stored |

---

### 4. Live Test Data (Real Patients — Verified 2026-05-29)

The following patients and visits exist in the local Bahmni instance and can be used directly in curl tests:

| Patient ID | Patient Name | patient_uuid | visit_uuid |
|------------|-------------|--------------|------------|
| `BDSEC200020` | Kim Kamuti | `1cda9b28-8380-4e34-8d6c-cd1db3a31399` | `a24b6433-ca57-41f7-896d-036fa766d5c0` |
| `BDSEC200019` | Joyce Jacob | `fca73bf0-59d8-4e68-86ca-a8e2a4f119ac` | `ebac52b7-5b07-4ad7-81c5-771a59886542` |
| `BDSEC200018` | Kesie Marry | `b56701eb-cdd3-4819-9257-6c8287053a6a` | `08687909-5ac0-42b9-a26f-39ab052f7438` |
| `BDSEC200017` | Eunice James | `9112ea16-7cf5-42aa-b215-efb43e2f5880` | `3911072a-1c13-4f15-9414-706f816b8756` |
| `BDSEC200016` | James Chao | `ec3bb34c-a188-4caf-85f0-0f6e4501df5f` | `b1b12666-48bc-44b8-a717-a789b00ad757` |
| `BDSEC200013` | Dennis Josepth | `0c60b25b-6b21-4cca-b939-c83af380c1d6` | `40fd3eae-4826-46ae-8540-b8b047ed8db1` |

---

### 5. curl Test Scripts (Part B)

Use `sale_id` values that have not been used before. A `sale_id` can be re-submitted any number of
times **as long as `payment_status` changes** — each distinct (`sale_id`, `payment_status`) pair
gets its own append-only history row (see §9); only re-sending the exact same pair is treated as a
duplicate.

#### Test 1 — No credentials → HTTP 401
```bash
curl -k -s -w "\nHTTP %{http_code}" \
  -X POST "https://localhost/openmrs/ws/rest/v1/odooconnector/billing/orders" \
  -H "Content-Type: application/json" \
  -d '{"sale_id":200}'
# Expected: {"status":"error","message":"Unauthorized..."} HTTP 401
```

#### Test 2 — Wrong token → HTTP 401
```bash
curl -k -s -w "\nHTTP %{http_code}" \
  -X POST "https://localhost/openmrs/ws/rest/v1/odooconnector/billing/orders" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer wrong-token" \
  -d '{"sale_id":200}'
# Expected: {"status":"error","message":"Unauthorized..."} HTTP 401
```

#### Test 3 — Cash patient, single service → HTTP 200
```bash
curl -k -s \
  -X POST "https://localhost/openmrs/ws/rest/v1/odooconnector/billing/orders" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token-123" \
  -d '{
    "sale_id": 201,
    "sale_name": "S00201",
    "patient_name": "Kim Kamuti",
    "patient_id": "BDSEC200020",
    "patient_uuid": "1cda9b28-8380-4e34-8d6c-cd1db3a31399",
    "visit_uuid":   "a24b6433-ca57-41f7-896d-036fa766d5c0",
    "amountDue":    0.00,
    "amountPaid":   500.00,
    "currency":     "ETB",
    "payment_status": "paid",
    "payment_date": "2026-05-29",
    "customer_type": "cash",
    "services": [{"serviceType": "Consultation", "price_unit": 500.00}]
  }'
# Expected: {"status":"success","internal_billing_id":"BILL-XXXXXX",...}
```

#### Test 4 — CBHI / waived patient → HTTP 200
```bash
curl -k -s \
  -X POST "https://localhost/openmrs/ws/rest/v1/odooconnector/billing/orders" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token-123" \
  -d '{
    "sale_id": 202,
    "sale_name": "S00202",
    "patient_name": "Joyce Jacob",
    "patient_id": "BDSEC200019",
    "patient_uuid": "fca73bf0-59d8-4e68-86ca-a8e2a4f119ac",
    "visit_uuid":   "ebac52b7-5b07-4ad7-81c5-771a59886542",
    "amountDue":    0.00,
    "amountPaid":   0.00,
    "currency":     "ETB",
    "payment_status": "waived",
    "payment_date": "2026-05-29",
    "customer_type": "cbhi",
    "services": [{"serviceType": "Consultation", "price_unit": 0.00}]
  }'
```

#### Test 5 — Multiple services in one order → HTTP 200
```bash
curl -k -s \
  -X POST "https://localhost/openmrs/ws/rest/v1/odooconnector/billing/orders" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token-123" \
  -d '{
    "sale_id": 203,
    "sale_name": "S00203",
    "patient_name": "Kesie Marry",
    "patient_id": "BDSEC200018",
    "patient_uuid": "b56701eb-cdd3-4819-9257-6c8287053a6a",
    "visit_uuid":   "08687909-5ac0-42b9-a26f-39ab052f7438",
    "amountDue":    250.00,
    "amountPaid":   750.00,
    "currency":     "ETB",
    "payment_status": "paid",
    "payment_date": "2026-05-29",
    "customer_type": "insurance",
    "services": [
      {"serviceType": "Consultation", "price_unit": 500.00},
      {"serviceType": "Lab_Order",    "price_unit": 500.00}
    ]
  }'
# Expected: two rows in odoo_billing_payment_status, internal_billing_id points to first row
```

#### Test 6 — Duplicate (sale_id, payment_status) → same BILL-XXXXXX returned
```bash
# Re-send Test 3 payload exactly (sale_id=201, payment_status=paid)
curl -k -s \
  -X POST "https://localhost/openmrs/ws/rest/v1/odooconnector/billing/orders" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token-123" \
  -d '{
    "sale_id": 201,
    "patient_uuid": "1cda9b28-8380-4e34-8d6c-cd1db3a31399",
    "visit_uuid":   "a24b6433-ca57-41f7-896d-036fa766d5c0",
    "payment_status": "paid",
    "services": [{"serviceType": "Consultation"}]
  }'
# Expected: {"message":"Billing order already processed (duplicate sale_id + payment_status)","internal_billing_id":"BILL-XXXXXX",...}
# internal_billing_id MUST match the one from Test 3
```

#### Test 6b — Status transition for the same sale_id → NEW row, NOT a duplicate (live-tested 2026-06-17)
```bash
# First push: PENDING
curl -k -s -X POST "https://localhost/openmrs/ws/rest/v1/odooconnector/billing/orders" \
  -H "Content-Type: application/json" -H "Authorization: Bearer test-token-123" \
  -d '{"sale_id":555,"sale_name":"S00555","patient_id":"BDSEC200024",
       "patient_uuid":"5d2216ac-00a7-460e-9bd6-a3f0ea97fbc4","visit_uuid":"bf625a64-7a01-4e64-bda1-1e299a345a9e",
       "amountDue":500.00,"amountPaid":0.00,"currency":"ETB","payment_status":"pending",
       "services":[{"serviceType":"Consultation","price_unit":500.00}]}'
# -> {"internal_billing_id":"BILL-000022", ...}  (new row, id=22, payment_status=PENDING)

# Second push, SAME sale_id, status now PAID — NOT treated as a duplicate
curl -k -s -X POST "https://localhost/openmrs/ws/rest/v1/odooconnector/billing/orders" \
  -H "Content-Type: application/json" -H "Authorization: Bearer test-token-123" \
  -d '{"sale_id":555,"sale_name":"S00555","patient_id":"BDSEC200024",
       "patient_uuid":"5d2216ac-00a7-460e-9bd6-a3f0ea97fbc4","visit_uuid":"bf625a64-7a01-4e64-bda1-1e299a345a9e",
       "amountDue":0.00,"amountPaid":500.00,"currency":"ETB","payment_status":"paid",
       "services":[{"serviceType":"Consultation","price_unit":500.00}]}'
# -> {"internal_billing_id":"BILL-000023", ...}  (a SECOND new row, id=23, payment_status=PAID — id=22 is untouched)

# Re-sending the PAID payload a third time IS a duplicate (same sale_id + same status)
# -> {"message":"... (duplicate sale_id + payment_status)","internal_billing_id":"BILL-000023", ...}  (still id=23, no third row)
```

#### Test 6c — Numeric patient_id in the payload is ignored, not stored (live-tested 2026-06-17)
```bash
curl -k -s -X POST "https://localhost/openmrs/ws/rest/v1/odooconnector/billing/orders" \
  -H "Content-Type: application/json" -H "Authorization: Bearer test-token-123" \
  -d '{"sale_id":556,"patient_id":"12345",
       "patient_uuid":"5d2216ac-00a7-460e-9bd6-a3f0ea97fbc4","visit_uuid":"bf625a64-7a01-4e64-bda1-1e299a345a9e",
       "payment_status":"pending","services":[{"serviceType":"Consultation"}]}'
# Succeeds (HTTP 200) but logs:
# WARN [BillingOrder] Payload patient_id='12345' is numeric — ignoring it, using resolved Bahmni identifier 'BDSEC200024' instead
# SELECT patient_id FROM odoo_billing_payment_status WHERE service_reference_id='556' -> 'BDSEC200024', NOT '12345'
```

#### Test 7 — Unknown patient_uuid → HTTP 400
```bash
curl -k -s -w "\nHTTP %{http_code}" \
  -X POST "https://localhost/openmrs/ws/rest/v1/odooconnector/billing/orders" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token-123" \
  -d '{
    "sale_id": 204,
    "patient_uuid": "00000000-0000-0000-0000-000000000000",
    "visit_uuid":   "a24b6433-ca57-41f7-896d-036fa766d5c0",
    "payment_status": "paid",
    "services": [{"serviceType": "Consultation"}]
  }'
# Expected: {"status":"error","message":"Patient not found for patient_uuid=00000000-..."} HTTP 400
```

#### Test 8 — Missing required fields → HTTP 400
```bash
curl -k -s -w "\nHTTP %{http_code}" \
  -X POST "https://localhost/openmrs/ws/rest/v1/odooconnector/billing/orders" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer test-token-123" \
  -d '{"patient_uuid": "1cda9b28-8380-4e34-8d6c-cd1db3a31399"}'
# Expected: {"status":"error","message":"sale_id, patient_uuid, and visit_uuid are required"} HTTP 400
```

---

### 6. Expected Responses

**Success — new order (HTTP 200):**
```json
{
  "status": "success",
  "message": "Billing order processed successfully",
  "external_sale_id": 201,
  "internal_billing_id": "BILL-000017",
  "processed_at": "2026-05-29T11:32:00Z"
}
```

**Success — duplicate (sale_id, payment_status) pair (HTTP 200, same `internal_billing_id`):**
```json
{
  "status": "success",
  "message": "Billing order already processed (duplicate sale_id + payment_status)",
  "external_sale_id": 201,
  "internal_billing_id": "BILL-000017",
  "processed_at": "2026-05-29T11:32:00Z"
}
```

**Patient has no identifier (HTTP 400):**
```json
{
  "status": "error",
  "message": "Patient <uuid> has no identifier — cannot process billing order"
}
```

**Unauthorized (HTTP 401):**
```json
{
  "status": "error",
  "message": "Unauthorized — provide a valid Bearer token or x-api-key"
}
```

**Unknown patient UUID (HTTP 400):**
```json
{
  "status": "error",
  "message": "Patient not found for patient_uuid=00000000-0000-0000-0000-000000000000"
}
```

**Unknown visit UUID (HTTP 400):**
```json
{
  "status": "error",
  "message": "Visit not found for visit_uuid=00000000-0000-0000-0000-000000000000"
}
```

**Missing required fields (HTTP 400):**
```json
{
  "status": "error",
  "message": "sale_id, patient_uuid, and visit_uuid are required"
}
```

---

### 7. OpenMRS Log Verification (Part B)

**Successful new order:**
```
INFO  BillingOrderController - [BillingOrder] POST /odooconnector/billing/orders — sale_id=201 patient_uuid=1cda9b28-... visit_uuid=a24b6433-...
INFO  BillingOrderService    - [BillingOrder] Received — sale_id=201 sale_name=S00201 patient_uuid=1cda9b28-... visit_uuid=a24b6433-...
INFO  BillingOrderService    - [BillingOrder] Mapped — patientId=82 visitId=25 paymentStatus=PAID amountDue=0.00 amountPaid=500.00 currency=ETB customerType=cash
INFO  BillingOrderService    - [BillingOrder] Saved record — id=17 serviceType=CONSULTATION status=PAID
```

**Duplicate (sale_id, payment_status):**
```
INFO  BillingOrderService    - [BillingOrder] Duplicate sale_id=201 payment_status=PAID — returning cached response (record id=17)
```

**Numeric patient_id in payload (live capture, 2026-06-17):**
```
WARN  BillingOrderService    - [BillingOrder] Payload patient_id='12345' is numeric — ignoring it, using resolved Bahmni identifier 'BDSEC200024' instead
```

**Auth failure:**
```
WARN  BillingOrderService    - [BillingOrder] Auth FAILED — invalid Bearer token (header present)
WARN  BillingOrderController - [BillingOrder] 401 Unauthorized — sale_id=201
```

---

### 8. End-to-End Test Checklist (Part B)

- [ ] Test 1: no auth header → HTTP 401
- [ ] Test 2: wrong Bearer token → HTTP 401
- [ ] Test 3: cash patient, `payment_status=paid` → HTTP 200, `internal_billing_id` returned
- [ ] Test 4: CBHI patient, `payment_status=waived` → HTTP 200
- [ ] Test 5: two services in one payload → HTTP 200, two rows in `odoo_billing_payment_status`
- [ ] Test 6: same `sale_id` + same `payment_status` re-submitted → HTTP 200, **identical** `internal_billing_id`, message "already processed"
- [ ] Test 6b: same `sale_id`, **different** `payment_status` (e.g. PENDING then PAID) → HTTP 200 both times, **two different** `internal_billing_id` values, **both** rows present in the table (history preserved, not overwritten)
- [ ] Test 6c: payload `patient_id` is a numeric string (e.g. `"12345"`) → HTTP 200, WARN logged, but the stored `patient_id` is the resolved Bahmni identifier, never `"12345"`
- [ ] Test 7: unknown `patient_uuid` → HTTP 400, message "Patient not found"
- [ ] Test 8: missing `sale_id` → HTTP 400, message lists all required fields
- [ ] Update `inboundBearerToken` in Global Properties → old token rejected, new token accepted (no restart needed)
- [ ] Verify `odoo_billing_payment_status` table rows via SQL — `patient_id` must always look like a Bahmni identifier (e.g. `BDSEC200024`), never a bare integer:
  ```sql
  SELECT id, patient_id, visit_id, service_type, service_reference_id,
         odoo_invoice_id, payment_status, amount_paid, currency
  FROM odoo_billing_payment_status
  ORDER BY id DESC LIMIT 10;
  ```
- [ ] For one `sale_id` pushed twice with different statuses, confirm both rows survive in order:
  ```sql
  SELECT id, patient_id, payment_status FROM odoo_billing_payment_status
  WHERE service_reference_id = '555' ORDER BY id;
  -- Expected: id=22 PENDING, id=23 PAID — both present, neither overwritten
  ```

---

### 9. Implementation Notes (Part B)

- **Idempotency key:** `(sale_id, payment_status)` — stored as `service_reference_id` + `payment_status`. A duplicate submission (same sale_id, same status) short-circuits and returns the original `internal_billing_id` without writing any new rows. A status **transition** for the same `sale_id` (e.g. PENDING → PAID) is *not* a duplicate and is persisted as a brand new row — see `OdooBillingPaymentStatusDao.getLatestByServiceReferenceIdAndStatus()`.
- **Append-only history:** `saveOrUpdatePaymentStatus()` never looks up and updates an existing row — every call inserts a new one. The full payment lifecycle for a (patient, visit, service) combination is preserved; gate checks (`isServicePaid`, `getPaymentStatus`) automatically pick up the most recent row via `ORDER BY odooSyncTimestamp DESC LIMIT 1` in `getByPatientVisitService()`, so no query logic changed to support this.
- **patient_id is always the Bahmni identifier string:** Resolved from `patient_uuid` via `patient.getPatientIdentifier().getIdentifier()` — never the internal numeric patient PK. The payload's own `patient_id` field is validated but never trusted for persistence: a numeric value is logged as a WARN and ignored; a non-numeric value that doesn't match the resolved identifier is logged as a WARN but the resolved value is still what's stored. A patient with no identifier at all is rejected with HTTP 400 rather than silently storing something wrong.
- **Schema migration (2026-06-17):** `odoo_billing_payment_status.patient_id` changed from `INT` (FK to `patient.patient_id`) to `VARCHAR(50)` holding the preferred patient identifier. Existing rows were backfilled from `patient_identifier WHERE preferred = 1`. There is no FK back to `patient` anymore (a string column can't reference a numeric PK) — referential correctness for `patient_id` is now enforced in `BillingOrderService`, not the database.
- **UUID resolution:** `patient_uuid` and `visit_uuid` are resolved via `PatientService` / `VisitService`. If either UUID is not found (or the patient has no identifier), the request is rejected with HTTP 400 before any data is written.
- **Proxy privileges:** The endpoint uses a custom Bearer token, not an OpenMRS session. `Context.addProxyPrivilege("Get Patients")` and `Context.addProxyPrivilege("Get Visits")` are applied only for the duration of the UUID/identifier lookups, then immediately removed.
- **services[] fan-out:** Each entry in `services[]` produces one new `odoo_billing_payment_status` row. The `internal_billing_id` in the response is `"BILL-"` + the database ID of the first row inserted in that request, zero-padded to 6 digits.
- **Payment status normalisation:** `payment_status` is uppercased on ingestion (`"paid"` → `"PAID"`) before it's used for the idempotency check or persisted, to match the gate-check values `PAID` and `WAIVED` used by `BillingPaymentGateInterceptor`.
- **BillingPaymentGateInterceptor** was updated alongside this change: it now resolves and compares the Bahmni identifier string (via `patient.getPatientIdentifier()`), not the numeric patient ID, since that's what `odoo_billing_payment_status.patient_id` now stores. A numeric `patientId` request param from a legacy caller is still accepted but resolved to the identifier with a WARN log.
- **No restart required:** Token changes via Global Properties take effect on the next request. The service reads the property fresh on each call.

---
---

## Part C — Consultation Payment Gate on the Patient Queue

### Scope

This gate applies to the **Patient Queue** screen only — the literal route
`#/default/patient/search` in the clinical app (the UI's own label for this screen, see
`PATIENT_QUEUE_TRANSLATION_KEY`), backed by `common/patient-search/controllers/patientsListController.js`
and `common/patient-search/views/patientsList.html`. It does **not** apply to the ADT ward list or
the registration module's own patient search — those are different workflows (inpatient bed
management, and finding/registering a patient before any visit exists).

It only gates the **CONSULTATION** queue tab. Other queue types configured via the
`org.bahmni.patient.search` extension (TRIAGE, COUNSELLING, INVESTIGATION) are not consultation
billing and navigate exactly as before.

### End-to-End Workflow

```
Patient Queue (clinical, CONSULTATION tab)
  ├─▶ List renders → markNotPaidForConsultationQueue() runs per visible row
  │         └─▶ GET /odoo/billing/is-paid?patientUuid=&visitUuid=&serviceType=CONSULTATION
  │               └─▶ row.notPaidForConsultation = !paid  →  "Not Paid" badge shown/hidden
  └─▶ Row clicked → $scope.forwardPatient()
        ├─▶ not CONSULTATION queue           → navigate immediately (unchanged)
        ├─▶ CONSULTATION, no active visit    → blocking popup, no navigation
        ├─▶ CONSULTATION, GET /is-paid=false → blocking popup, no navigation
        └─▶ CONSULTATION, GET /is-paid=true  → navigate to dashboard (unchanged)
```

### 1. Backend — extended `/is-paid` endpoint

```
GET /openmrs/ws/rest/v1/odoo/billing/is-paid
    ?(patientId=<identifier> | patientUuid=<uuid>)
    &(visitId=<int>           | visitUuid=<uuid>)
    &serviceType=CONSULTATION
```

Either form of patient/visit identification works — `patientUuid`/`visitUuid` (what the Patient
Queue has on hand) or the original `patientId`/`visitId` (still supported, unchanged, for any
existing caller). Resolution is shared with `BillingPaymentGateInterceptor` via the new
`PatientVisitResolver` class (`omod/.../web/PatientVisitResolver.java`) — both now resolve a
numeric-or-UUID patient/visit reference the same way, instead of duplicating the logic.

**Fail-safe behaviour:** if either side can't be resolved, the endpoint returns `200
{"paid": false, "reason": "Could not resolve patient and/or visit"}` rather than an error — an
ambiguous patient/visit blocks access just like a missing payment record does.

**Live-tested (2026-06-17):**
```bash
# PAID — real patient/visit with a PAID CONSULTATION record
curl -k -s -b /tmp/omrs.txt "https://localhost/openmrs/ws/rest/v1/odoo/billing/is-paid?patientUuid=5d2216ac-00a7-460e-9bd6-a3f0ea97fbc4&visitUuid=bf625a64-7a01-4e64-bda1-1e299a345a9e&serviceType=CONSULTATION"
# -> {"paid":true,"patientId":"BDSEC200024","visitId":36,"serviceType":"CONSULTATION"}

# No record at all for this visit/service
curl -k -s -b /tmp/omrs.txt "https://localhost/openmrs/ws/rest/v1/odoo/billing/is-paid?patientUuid=b6bd5037-4450-4bc0-912e-5f6124a38ec8&visitUuid=a1c2cdd2-a8fe-4866-964d-41a75d6fcf14&serviceType=CONSULTATION"
# -> {"paid":false,"patientId":"BDSEC200023","visitId":33,"serviceType":"CONSULTATION"}

# Legacy patientId/visitId form still works unchanged
curl -k -s -b /tmp/omrs.txt "https://localhost/openmrs/ws/rest/v1/odoo/billing/is-paid?patientId=BDSEC200024&visitId=36&serviceType=CONSULTATION"
# -> {"paid":true,...}

# Unresolvable patient/visit -> fail-safe block, not an error
curl -k -s -b /tmp/omrs.txt "https://localhost/openmrs/ws/rest/v1/odoo/billing/is-paid?patientUuid=00000000-0000-0000-0000-000000000000&visitUuid=00000000-0000-0000-0000-000000000000&serviceType=CONSULTATION"
# -> {"paid":false,"reason":"Could not resolve patient and/or visit"}
```

### 2. Frontend — files touched

- `common/patient-search/services/consultationPaymentGateService.js` (new) — `isConsultationPaid(patientUuid, visitUuid)`, always resolves to a boolean; any HTTP failure resolves to `false` (fail-safe).
- `common/patient-search/controllers/patientsListController.js` — `forwardPatient()` now gates on the CONSULTATION queue type before calling the existing navigation logic (renamed internally to `proceedToDashboard()`); a new `markNotPaidForConsultationQueue()` populates the badge flag on every visible row.
- `common/patient-search/views/patientsList.html` — a `not-paid-indication` icon added next to the existing bed (`ipd-indication`) icon, in both the table and tile views.
- `styles/clinical/_patientSearch.scss` (+ compiled `styles/clinical.css`, since this dev setup serves checked-in compiled CSS directly rather than running a Sass build) — red badge styling.
- `i18n/clinical/locale_en.json` — `PAYMENT_REQUIRED_BEFORE_DASHBOARD_TRANSLATION_KEY` (popup message, exact text from spec) and `NOT_PAID_TRANSLATION_KEY` (badge tooltip). The popup's OK button reuses the existing generic `OKAY_LABEL` key.
- Every `index.html` that loads `patientsListController.js` (clinical, adt, bedmanagement, orders, document-upload, registration, ot) got a matching `<script>` tag for the new service — this app has no bundler/auto-discovery for `ui/app/`, each page lists its scripts explicitly.

The popup itself reuses the existing `confirmBox` service (`common/ui-helper/services/confirmBoxService.js`) — the same blocking-modal-with-button(s) mechanism already used elsewhere in the app (e.g. `consultationController.js`'s save confirmation) — no new popup mechanism was built.

### 3. Existing backend enforcement (unchanged)

`BillingPaymentGateInterceptor` already blocks POST/PUT to `/bahmniencounter`, `/order`, etc. with
HTTP 402 when the relevant service isn't paid — that's the "API-level" enforcement layer the task
asked for, and it required no behavioral changes here (only the de-duplication into
`PatientVisitResolver`). The Patient Queue gate is an additional **UX-level** guard that stops a
clinician from wasting time entering an unpaid patient's dashboard in the first place; the actual
security boundary for clinical actions remains the interceptor.

### 4. Manual Test Checklist (Part C)

- [ ] Open the Patient Queue, CONSULTATION tab: patients with no PAID record show the red "Not Paid" badge next to the bed icon
- [ ] Click an unpaid patient → popup appears immediately with the exact message: "This patient has not paid the consultation fee. Please complete payment before proceeding." → clicking OK dismisses it, dashboard does **not** open
- [ ] Push a PAID billing order for that patient/visit (`POST /odooconnector/billing/orders`), refresh the queue → badge disappears
- [ ] Click the now-paid patient → dashboard opens normally, no popup
- [ ] A patient with no active visit on the CONSULTATION tab → badge shown, click blocked (no `/is-paid` call needed — no visit, no record possible)
- [ ] Switch to a non-CONSULTATION tab (if configured, e.g. TRIAGE) → no badges shown, clicking any patient navigates immediately
- [ ] Temporarily break connectivity to the `/is-paid` endpoint (or stop the OpenMRS container) → clicking a patient on the CONSULTATION tab is blocked (fail-safe), not silently allowed through
