-- ============================================================================
-- FEAT-S2-001: Esquema inicial de gestión de casos de fraude
-- Historia: HU-S2-001 · Flujo: FM-S2-002
-- ============================================================================

-- Catálogo de estados de caso
CREATE TABLE case_state (
    code        VARCHAR(32) PRIMARY KEY,
    name        VARCHAR(128) NOT NULL,
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabla principal de casos
CREATE TABLE fraud_case (
    id            BIGSERIAL PRIMARY KEY,
    transaction_id VARCHAR(128) NOT NULL,
    score         DECIMAL(5,2),
    state_code    VARCHAR(32) NOT NULL,
    opened_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_fraud_case_transaction UNIQUE (transaction_id),
    CONSTRAINT fk_fraud_case_state
        FOREIGN KEY (state_code) REFERENCES case_state(code)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Índices para consultas frecuentes
CREATE INDEX idx_fraud_case_state ON fraud_case(state_code);
CREATE INDEX idx_fraud_case_opened_at ON fraud_case(opened_at);

-- Tabla de asignación de casos a analistas
CREATE TABLE case_assignment (
    id            BIGSERIAL PRIMARY KEY,
    case_id       BIGINT NOT NULL,
    analyst_id    VARCHAR(128) NOT NULL,
    analyst_email VARCHAR(256) NOT NULL,
    assigned_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    unassigned_at TIMESTAMPTZ,
    CONSTRAINT fk_case_assignment_case
        FOREIGN KEY (case_id) REFERENCES fraud_case(id)
        ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX idx_case_assignment_case ON case_assignment(case_id);
CREATE INDEX idx_case_assignment_analyst ON case_assignment(analyst_id);

-- Tabla de resolución de casos
CREATE TABLE case_resolution (
    id            BIGSERIAL PRIMARY KEY,
    case_id       BIGINT NOT NULL UNIQUE,
    decision      VARCHAR(32) NOT NULL,
    analyst_id    VARCHAR(128) NOT NULL,
    resolved_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    observations  TEXT,
    CONSTRAINT fk_case_resolution_case
        FOREIGN KEY (case_id) REFERENCES fraud_case(id)
        ON DELETE RESTRICT ON UPDATE CASCADE
);

-- Estados iniciales del catálogo
INSERT INTO case_state (code, name, description) VALUES
    ('NEW',           'Nuevo',            'Caso creado, pendiente de revisión'),
    ('UNDER_REVIEW',  'En revisión',      'Asignado a analista, en evaluación'),
    ('PENDING_INFO',  'Pendiente info',   'Se requiere documentación adicional'),
    ('ESCALATED',     'Escalado',         'Elevado a supervisor por complejidad'),
    ('RESOLVED',      'Resuelto',         'Decisión tomada y documentada'),
    ('DISMISSED',     'Descartado',       'Caso cerrado sin acción de fraude');
