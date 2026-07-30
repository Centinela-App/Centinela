-- ============================================================================
-- FEAT-S2-001: Tabla de auditoría inmutable (append-only)
-- Historia: HU-S2-001 · Criterio: Auditoría no admite UPDATE/DELETE
-- ============================================================================

CREATE TABLE case_audit (
    id           BIGSERIAL PRIMARY KEY,
    case_id      BIGINT NOT NULL,
    field_name   VARCHAR(64) NOT NULL,
    old_value    TEXT,
    new_value    TEXT,
    changed_by   VARCHAR(256) NOT NULL,
    changed_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    change_type  VARCHAR(32) NOT NULL,
    CONSTRAINT fk_case_audit_case
        FOREIGN KEY (case_id) REFERENCES fraud_case(id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

CREATE INDEX idx_case_audit_case ON case_audit(case_id);
CREATE INDEX idx_case_audit_changed_at ON case_audit(changed_at);

-- ============================================================================
-- Restricción de inmutabilidad: solo INSERT permitido
-- PostgreSQL: regla que rechaza UPDATE y DELETE sobre case_audit
-- ============================================================================
CREATE OR REPLACE RULE case_audit_no_update AS
    ON UPDATE TO case_audit
    DO INSTEAD NOTHING;

CREATE OR REPLACE RULE case_audit_no_delete AS
    ON DELETE TO case_audit
    DO INSTEAD NOTHING;

-- Comentario de documentación
COMMENT ON TABLE case_audit IS
    'Tabla de auditoría inmutable (append-only). '
    'Las reglas case_audit_no_update y case_audit_no_delete '
    'rechazan cualquier intento de modificación o borrado.';
