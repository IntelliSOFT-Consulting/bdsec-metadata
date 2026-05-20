-- =============================================================================
-- odoo_billing_payment_status
-- Payment gate table: stores billing status pushed from Odoo so that Bahmni
-- can block patients from accessing unpaid clinical services.
--
-- Usage: run this script directly when the Liquibase migration has not yet
--        been applied, e.g. during local dev or a manual DB bootstrap.
-- =============================================================================

CREATE TABLE IF NOT EXISTS odoo_billing_payment_status (
    id                   INT            NOT NULL AUTO_INCREMENT,
    patient_id           INT            NOT NULL COMMENT 'FK → patient.patient_id',
    visit_id             INT            NOT NULL COMMENT 'FK → visit.visit_id',
    encounter_id         INT            NULL     COMMENT 'FK → encounter.encounter_id (optional)',
    service_type         VARCHAR(100)   NOT NULL COMMENT 'CONSULTATION | BED | LAB_ORDER | MEDICATION | PROCEDURE | RADIOLOGY | DENTAL',
    service_reference_id VARCHAR(255)   NULL     COMMENT 'Odoo invoice / order reference',
    odoo_invoice_id      VARCHAR(255)   NULL     COMMENT 'Odoo invoice ID for traceability',
    payment_status       VARCHAR(50)    NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING | PAID | WAIVED | CANCELLED',
    amount_due           DECIMAL(10,2)  NULL,
    amount_paid          DECIMAL(10,2)  NULL,
    currency             VARCHAR(10)    NULL     DEFAULT 'KES',
    payment_date         DATETIME       NULL     COMMENT 'Timestamp when payment was confirmed',
    odoo_sync_timestamp  DATETIME       NOT NULL COMMENT 'When Odoo last pushed this record',
    created_at           DATETIME       NOT NULL DEFAULT NOW(),
    updated_at           DATETIME       NOT NULL DEFAULT NOW() ON UPDATE NOW(),
    voided               TINYINT(1)     NOT NULL DEFAULT 0,
    voided_by            INT            NULL     COMMENT 'FK → users.user_id',
    void_reason          VARCHAR(255)   NULL,
    uuid                 CHAR(38)       NOT NULL COMMENT 'FHIR UUID',

    PRIMARY KEY (id),
    UNIQUE  KEY uq_obps_uuid        (uuid),

    CONSTRAINT fk_obps_patient    FOREIGN KEY (patient_id)   REFERENCES patient(patient_id),
    CONSTRAINT fk_obps_visit      FOREIGN KEY (visit_id)     REFERENCES visit(visit_id),
    CONSTRAINT fk_obps_encounter  FOREIGN KEY (encounter_id) REFERENCES encounter(encounter_id),
    CONSTRAINT fk_obps_voided_by  FOREIGN KEY (voided_by)    REFERENCES users(user_id)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Odoo → Bahmni payment gate records';

-- Indexes
CREATE INDEX idx_obps_patient_id     ON odoo_billing_payment_status (patient_id);
CREATE INDEX idx_obps_visit_id       ON odoo_billing_payment_status (visit_id);
CREATE INDEX idx_obps_payment_status ON odoo_billing_payment_status (payment_status);
CREATE INDEX idx_obps_service_type   ON odoo_billing_payment_status (service_type);
-- Composite: the most common gate-check query
CREATE INDEX idx_obps_pvs            ON odoo_billing_payment_status (patient_id, visit_id, service_type);
