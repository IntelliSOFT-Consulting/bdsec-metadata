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
        └─▶ POST /openmrs/ws/rest/v1/odooconnector/consultation-fee
              └─▶ ConsultationFeeController  (validate fields)
                    └─▶ ConsultationFeeOdooService
                          ├─▶ POST https://bdsec.grace-erp-consultancy.com/web/session/authenticate
                          │         (JSON-RPC auth → get session_id from Set-Cookie header)
                          └─▶ POST https://bdsec.grace-erp-consultancy.com/api/bdsec/sales
                                    (consultation sale order payload + Cookie: session_id)
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
  "warnings": []
}
```

### Odoo unreachable (encounter still saved — non-fatal)

```json
{
  "status": "consultation_logged",
  "error": "Failed to connect to https://bdsec.grace-erp-consultancy.com: Connection timed out",
  "patientUuid": "3b6a5e2a-1234-4b9c-a832-000000000001",
  "VisitUuid": "9f3d0c11-abcd-4321-bcde-000000000002"
}
```

### Validation failure — missing required field

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

On Odoo unreachability:
```
ERROR ConsultationFeeOdooService - [ConsultationFee] Failed to reach Odoo — encounter already saved, payload not forwarded: ...
```

---

## 8. End-to-End Test Checklist

- [ ] Register a new patient (page 1: name, DOB, gender, patient ID)
- [ ] On page 2 fill: Consultation Fee, Payment Method (`free` or `cash`), Mode of Payment (`CBHI` or `OOP`)
- [ ] Click **Save**
- [ ] Browser console shows: `[ConsultationFee] Preparing to sync — patientId: ABC2XXXXX`
- [ ] Browser console shows: `[ConsultationFee] Synced to Odoo connector successfully`
- [ ] `openmrs.log` shows auth succeeded and sale order created
- [ ] Odoo back-office shows a new draft sale order (S000XX) for the patient
- [ ] Repeat with Odoo temporarily unreachable: encounter still saves, browser shows warning toast, log shows `consultation_logged`
- [ ] Test with missing `patientUuid` in payload: controller returns `{"status":"rejected",...}`

---

## 9. Implementation Notes (Part A)

- `default_code` is always `"consultation"` — hardcoded in `ConsultationFeeOdooService.buildSalesPayloadJson()`. Odoo resolves the product price from this code.
- `quantity` is always `1` — hardcoded alongside `default_code`.
- `shop_id` comes from the `odooconnector.consultation.shopId` global property (integer, default `1`).
- The Bahmni encounter save is **never blocked** by Odoo failures. If Odoo is down, the service logs the error and returns `status=consultation_logged`.
- Session authentication is performed fresh on every request. Odoo sessions are short-lived; caching was deliberately not added to avoid stale-session bugs.
- `Mode of Payment` concept answers are automatically lowercased before sending (`"Cash"` → `"cash"`) to satisfy Odoo's case-sensitive Payment_type validation.
- The sync fires on every Save regardless of whether a "Consultation Fee" observation exists — Odoo determines the price from the `consultation` product code.

---

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
| `sale_id` | integer | **Yes** | Odoo sale order ID — used as the idempotency key |
| `sale_name` | string | No | e.g. `"S00042"` — stored as `odoo_invoice_id` |
| `patient_name` | string | No | Informational — not stored |
| `patient_id` | string | No | Bahmni identifier e.g. `"BDSEC200010"` — informational |
| `patient_uuid` | string (UUID) | **Yes** | Resolved to OpenMRS patient integer ID |
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

Use `sale_id` values that have not been used before — each `sale_id` can only be submitted once (idempotency). Increment the number for each new test run.

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

#### Test 6 — Duplicate sale_id → same BILL-XXXXXX returned
```bash
# Re-send Test 3 payload exactly (sale_id=201)
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
# Expected: {"message":"Billing order already processed (duplicate sale_id)","internal_billing_id":"BILL-XXXXXX",...}
# internal_billing_id MUST match the one from Test 3
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

**Success — duplicate sale_id (HTTP 200, same `internal_billing_id`):**
```json
{
  "status": "success",
  "message": "Billing order already processed (duplicate sale_id)",
  "external_sale_id": 201,
  "internal_billing_id": "BILL-000017",
  "processed_at": "2026-05-29T11:32:00Z"
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

**Duplicate sale_id:**
```
INFO  BillingOrderService    - [BillingOrder] Duplicate sale_id=201 — returning cached response (record id=17)
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
- [ ] Test 6: same `sale_id` re-submitted → HTTP 200, **identical** `internal_billing_id`, message "already processed"
- [ ] Test 7: unknown `patient_uuid` → HTTP 400, message "Patient not found"
- [ ] Test 8: missing `sale_id` → HTTP 400, message lists all required fields
- [ ] Update `inboundBearerToken` in Global Properties → old token rejected, new token accepted (no restart needed)
- [ ] Verify `odoo_billing_payment_status` table rows via SQL:
  ```sql
  SELECT id, patient_id, visit_id, service_type, service_reference_id,
         odoo_invoice_id, payment_status, amount_paid, currency
  FROM odoo_billing_payment_status
  ORDER BY id DESC LIMIT 10;
  ```

---

### 9. Implementation Notes (Part B)

- **Idempotency key:** `sale_id` is stored as `service_reference_id`. On a duplicate submission the endpoint short-circuits and returns the original `internal_billing_id` without writing any new rows.
- **UUID resolution:** `patient_uuid` and `visit_uuid` are resolved to OpenMRS integer IDs via `PatientService` / `VisitService`. If either UUID is not found, the request is rejected with HTTP 400 before any data is written.
- **Proxy privileges:** The endpoint uses a custom Bearer token, not an OpenMRS session. `Context.addProxyPrivilege("Get Patients")` and `Context.addProxyPrivilege("Get Visits")` are applied only for the duration of the UUID lookups, then immediately removed. This is the standard OpenMRS pattern for cross-cutting access without a user context.
- **services[] fan-out:** Each entry in `services[]` produces one `odoo_billing_payment_status` row keyed on (patientId, visitId, serviceType). The `internal_billing_id` in the response is `"BILL-"` + the database ID of the first row, zero-padded to 6 digits.
- **Payment status normalisation:** `payment_status` is uppercased on ingestion (`"paid"` → `"PAID"`) to match the gate-check values `PAID` and `WAIVED` used by `BillingPaymentGateInterceptor`.
- **No restart required:** Token changes via Global Properties take effect on the next request. The service reads the property fresh on each call.
