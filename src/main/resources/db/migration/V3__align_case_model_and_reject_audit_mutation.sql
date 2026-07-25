-- ============================================================================
-- ISS-S2-010 corrective migration
-- Aligns the JPA model with the relational schema without rewriting migrations
-- that may already have been applied in a shared environment.
-- ============================================================================

ALTER TABLE fraud_case
    ALTER COLUMN score SET NOT NULL;

ALTER TABLE case_audit
    ADD COLUMN IF NOT EXISTS details TEXT;

DROP RULE IF EXISTS case_audit_no_update ON case_audit;
DROP RULE IF EXISTS case_audit_no_delete ON case_audit;

CREATE OR REPLACE FUNCTION reject_case_audit_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'case_audit is append-only; % is not allowed', TG_OP;
END;
$$;

DROP TRIGGER IF EXISTS trg_case_audit_immutable ON case_audit;
CREATE TRIGGER trg_case_audit_immutable
    BEFORE UPDATE OR DELETE ON case_audit
    FOR EACH ROW
    EXECUTE FUNCTION reject_case_audit_mutation();

COMMENT ON TABLE case_audit IS
    'Append-only audit log. UPDATE and DELETE are rejected by trg_case_audit_immutable.';
