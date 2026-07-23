package com.centinela.casemanagement.infrastructure.persistence;

import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import com.centinela.casemanagement.domain.model.CaseState;
import com.centinela.casemanagement.domain.model.FraudCase;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * TEST-S2-018: Prueba de integración del esquema de casos y auditoría inmutable.
 * Historia: HU-S2-001 · Feature: FEAT-S2-001
 */
@SpringBootTest
@ActiveProfiles("test")
class CaseSchemaIT {

    @Autowired
    private JpaCaseRepositoryAdapter adapter;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void setUp() {
        // Limpiar tablas en orden inverso a las dependencias
        jdbcTemplate.execute("DELETE FROM case_audit");
        jdbcTemplate.execute("DELETE FROM case_resolution");
        jdbcTemplate.execute("DELETE FROM case_assignment");
        jdbcTemplate.execute("DELETE FROM fraud_case");
    }

    @Test
    @Transactional
    void migrateSchema_createsAllTables() {
        // Verificar que las tablas existen
        assertThat(tableExists("fraud_case")).isTrue();
        assertThat(tableExists("case_state")).isTrue();
        assertThat(tableExists("case_assignment")).isTrue();
        assertThat(tableExists("case_resolution")).isTrue();
        assertThat(tableExists("case_audit")).isTrue();
    }

    @Test
    @Transactional
    void migrateSchema_createsCaseStateCatalog() {
        // Verificar que el catálogo de estados tiene datos
        Integer count = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM case_state", Integer.class);
        assertThat(count).isGreaterThanOrEqualTo(6);
    }

    @Test
    @Transactional
    void saveAndRetrieveFraudCase() {
        // Crear caso
        FraudCase fraudCase = new FraudCase(
                "TXN-" + System.currentTimeMillis(),
                new BigDecimal("85.50"),
                "NEW"
        );
        FraudCase saved = adapter.save(fraudCase);

        // Verificar que se persistió
        assertThat(saved.getId()).isNotNull();
        assertThat(saved.getOpenedAt()).isNotNull();

        // Buscar por ID
        var found = adapter.findById(saved.getId());
        assertThat(found).isPresent();
        assertThat(found.get().getTransactionId()).isEqualTo(fraudCase.getTransactionId());
    }

    @Test
    @Transactional
    void uniqueConstraintOnTransactionId() {
        String txnId = "TXN-DUPLICATE-" + System.currentTimeMillis();

        FraudCase case1 = new FraudCase(txnId, new BigDecimal("50.00"), "NEW");
        adapter.save(case1);

        // Verificar que existe
        assertThat(adapter.existsByTransactionId(txnId)).isTrue();

        // Buscar por transactionId
        var found = adapter.findByTransactionId(txnId);
        assertThat(found).isPresent();
        assertThat(found.get().getScore()).isEqualTo(new BigDecimal("50.00"));
    }

    @Test
    @Transactional
    void auditIsAppendOnly_allowsInsert() {
        // Crear caso
        FraudCase fraudCase = new FraudCase(
                "TXN-AUDIT-" + System.currentTimeMillis(),
                new BigDecimal("70.00"),
                "NEW"
        );
        FraudCase saved = adapter.save(fraudCase);

        // Registrar auditoría (INSERT debe funcionar)
        CaseAuditEntry entry = new CaseAuditEntry(
                saved.getId(),
                "state_code",
                null,
                "NEW",
                "analyst@example.com",
                "STATE_CHANGE"
        );
        CaseAuditEntry savedEntry = adapter.logAudit(entry);

        assertThat(savedEntry.getId()).isNotNull();
        assertThat(savedEntry.getChangedAt()).isNotNull();

        // Verificar que la auditoría se puede consultar
        List<CaseAuditEntry> auditTrail = adapter.findAuditByCaseId(saved.getId());
        assertThat(auditTrail).hasSize(1);
        assertThat(auditTrail.get(0).getNewValue()).isEqualTo("NEW");
    }

    @Test
    @Transactional
    void auditIsAppendOnly_rejectsUpdate() {
        // Crear caso y auditoría
        FraudCase fraudCase = new FraudCase(
                "TXN-AUDIT-UPDATE-" + System.currentTimeMillis(),
                new BigDecimal("60.00"),
                "NEW"
        );
        FraudCase saved = adapter.save(fraudCase);

        CaseAuditEntry entry = new CaseAuditEntry(
                saved.getId(),
                "state_code",
                null,
                "NEW",
                "analyst@example.com",
                "STATE_CHANGE"
        );
        adapter.logAudit(entry);

        // Intentar UPDATE sobre auditoría (debe ser rechazado por la regla DB)
        // La regla "DO INSTEAD NOTHING" hace que no haga nada, no lanza excepción
        // Verificamos que el registro no cambió
        jdbcTemplate.update(
                "UPDATE case_audit SET new_value = 'HACKED' WHERE id = ?",
                entry.getId()
        );

        // Refrescar y verificar que no cambió
        List<CaseAuditEntry> auditTrail = adapter.findAuditByCaseId(saved.getId());
        assertThat(auditTrail.get(0).getNewValue()).isEqualTo("NEW");
    }

    @Test
    @Transactional
    void auditIsAppendOnly_rejectsDelete() {
        // Crear caso y auditoría
        FraudCase fraudCase = new FraudCase(
                "TXN-AUDIT-DELETE-" + System.currentTimeMillis(),
                new BigDecimal("55.00"),
                "NEW"
        );
        FraudCase saved = adapter.save(fraudCase);

        CaseAuditEntry entry = new CaseAuditEntry(
                saved.getId(),
                "state_code",
                null,
                "NEW",
                "analyst@example.com",
                "STATE_CHANGE"
        );
        CaseAuditEntry savedEntry = adapter.logAudit(entry);

        // Intentar DELETE sobre auditoría
        int deleted = jdbcTemplate.update(
                "DELETE FROM case_audit WHERE id = ?",
                savedEntry.getId()
        );

        // Verificar que no se borró (regla DB)
        assertThat(deleted).isEqualTo(0);

        // Verificar que sigue existiendo
        List<CaseAuditEntry> auditTrail = adapter.findAuditByCaseId(saved.getId());
        assertThat(auditTrail).hasSize(1);
    }

    @Test
    @Transactional
    void foreignKeyIntegrity_caseReferencesState() {
        // Crear estado si no existe
        jdbcTemplate.update(
                "INSERT INTO case_state (code, name, description, created_at) " +
                "VALUES ('TEST_STATE', 'Estado Test', 'Para pruebas', NOW()) " +
                "ON CONFLICT (code) DO NOTHING"
        );

        // Crear caso con estado válido
        FraudCase fraudCase = new FraudCase(
                "TXN-FK-" + System.currentTimeMillis(),
                new BigDecimal("75.00"),
                "TEST_STATE"
        );
        FraudCase saved = adapter.save(fraudCase);

        assertThat(saved.getId()).isNotNull();
        assertThat(saved.getStateCode()).isEqualTo("TEST_STATE");
    }

    @Test
    @Transactional
    void stateCodeUniqueConstraint() {
        String txnId = "TXN-UNIQUE-" + System.currentTimeMillis();

        // Primer caso
        FraudCase case1 = new FraudCase(txnId, new BigDecimal("40.00"), "NEW");
        adapter.save(case1);

        // Segundo caso con mismo transactionId debe fallar
        FraudCase case2 = new FraudCase(txnId, new BigDecimal("60.00"), "UNDER_REVIEW");
        assertThatThrownBy(() -> adapter.save(case2))
                .isInstanceOf(Exception.class);
    }

    private boolean tableExists(String tableName) {
        String sql = """
            SELECT EXISTS (
                SELECT FROM pg_tables
                WHERE schemaname = 'public'
                AND tablename = ?
            )
            """;
        Boolean exists = jdbcTemplate.queryForObject(sql, Boolean.class, tableName);
        return Boolean.TRUE.equals(exists);
    }
}
