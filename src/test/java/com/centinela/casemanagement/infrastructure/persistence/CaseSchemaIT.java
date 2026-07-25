package com.centinela.casemanagement.infrastructure.persistence;

import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import com.centinela.casemanagement.domain.model.CaseState;
import com.centinela.casemanagement.domain.model.Case_;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.context.annotation.Import;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.OffsetDateTime;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest(properties = {
        "spring.flyway.enabled=false",
        "spring.jpa.hibernate.ddl-auto=create-drop"
})
@Import(JpaCaseRepositoryAdapter.class)
class CaseSchemaIT {
    @Autowired JpaCaseRepositoryAdapter adapter;
    @Autowired EntityManager entityManager;

    @BeforeEach
    void seedState() {
        if (entityManager.find(CaseState.class, "NEW") == null) {
            entityManager.persist(new CaseState("NEW", "Nuevo", "Pendiente de revision"));
            entityManager.flush();
        }
    }

    @Test
    void persists_case_and_append_only_audit_atomically() {
        OffsetDateTime now = OffsetDateTime.parse("2026-07-25T15:00:00Z");
        Case_ saved = adapter.saveCaseWithAudit(
                new Case_(null, "tx-schema-1", new BigDecimal("90"), Case_.CaseStatus.NEW, now, now),
                new CaseAuditEntry(null, "state_code", null, "NEW", "system", "OPENED", "contract=flagged-case-v1"));

        assertThat(saved.caseId()).isNotNull();
        assertThat(adapter.findByTransactionId("tx-schema-1")).contains(saved);
        assertThat(adapter.countByCaseId(saved.caseId())).isEqualTo(1);
        assertThat(adapter.findByCaseIdOrderByChangedAtAsc(saved.caseId()).getFirst().getDetails())
                .isEqualTo("contract=flagged-case-v1");
    }

    @Test
    void migrations_define_the_five_tables_and_reject_audit_mutation() throws Exception {
        String v1 = resource("/db/migration/V1__case_schema.sql");
        String v2 = resource("/db/migration/V2__case_audit_immutable.sql");
        String v3 = resource("/db/migration/V3__align_case_model_and_reject_audit_mutation.sql");

        assertThat(v1).contains("CREATE TABLE fraud_case", "CREATE TABLE case_state",
                "CREATE TABLE case_assignment", "CREATE TABLE case_resolution");
        assertThat(v2).contains("CREATE TABLE case_audit");
        assertThat(v3).contains("ADD COLUMN IF NOT EXISTS details", "BEFORE UPDATE OR DELETE",
                "RAISE EXCEPTION", "ALTER COLUMN score SET NOT NULL");
    }

    private String resource(String name) throws Exception {
        try (var stream = getClass().getResourceAsStream(name)) {
            if (stream == null) throw new IllegalStateException("Missing resource " + name);
            return new String(stream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }
}
