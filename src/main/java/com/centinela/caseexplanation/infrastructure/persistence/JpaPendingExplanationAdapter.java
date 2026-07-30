package com.centinela.caseexplanation.infrastructure.persistence;

import com.centinela.caseexplanation.application.port.out.PendingExplanationPort;
import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import com.centinela.casemanagement.domain.model.Case_;
import com.centinela.casemanagement.domain.model.FraudCase;
import com.centinela.casemanagement.infrastructure.persistence.JpaCaseRepositoryAdapter;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import jakarta.transaction.Transactional;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.List;
import java.util.Objects;

/** Adaptador JPA sobre {@code fraud_case} para el ciclo de vida de la explicacion. */
@Component
public class JpaPendingExplanationAdapter implements PendingExplanationPort {

    private static final String SYSTEM_USER = "system:case-explainer";

    @PersistenceContext
    private EntityManager entityManager;

    /**
     * La bitacora de auditoria pertenece a {@code casemanagement}. Se escribe a traves de
     * su adaptador en lugar de manipular su entidad: el explicador es un consumidor de esa
     * capacidad, no un coautor de su esquema.
     */
    private final JpaCaseRepositoryAdapter caseRepository;

    public JpaPendingExplanationAdapter(JpaCaseRepositoryAdapter caseRepository) {
        this.caseRepository = Objects.requireNonNull(caseRepository, "caseRepository is required");
    }

    @Override
    public List<PendingCase> findPending(int limit) {
        return entityManager.createQuery(
                        "SELECT c FROM FraudCase c "
                                + "WHERE c.explanationState = :state "
                                + "ORDER BY c.openedAt ASC",
                        FraudCase.class)
                .setParameter("state", Case_.ExplanationState.PENDING.name())
                .setMaxResults(limit)
                .getResultList()
                .stream()
                .map(entity -> new PendingCase(
                        entity.getId(),
                        entity.getTransactionId(),
                        entity.getTraceparent(),
                        entity.getExplanationAttempts()))
                .toList();
    }

    /**
     * Escribe explicacion, estado y traza de auditoria en una sola transaccion.
     *
     * <p>Si se separaran, una caida entre ambas escrituras dejaria un caso marcado como
     * explicado sin rastro de quien lo explico, o al reves.
     */
    @Override
    @Transactional
    public void attachExplanation(Long caseId, String explanation, Instant generatedAt) {
        FraudCase entity = require(caseId);
        entity.attachExplanation(explanation, generatedAt);
        entityManager.merge(entity);
        audit(caseId, "EXPLANATION_GENERATED",
                "attempts=" + entity.getExplanationAttempts());
        entityManager.flush();
    }

    @Override
    @Transactional
    public void recordFailure(Long caseId, int maxAttempts, String reason) {
        FraudCase entity = require(caseId);
        entity.recordFailedExplanationAttempt(maxAttempts);
        entityManager.merge(entity);
        audit(caseId, "EXPLANATION_FAILED",
                "attempts=" + entity.getExplanationAttempts()
                        + "; state=" + entity.getExplanationState()
                        + "; reason=" + truncate(reason));
        entityManager.flush();
    }

    private FraudCase require(Long caseId) {
        FraudCase entity = entityManager.find(FraudCase.class, caseId);
        if (entity == null) {
            throw new IllegalStateException("Case " + caseId + " no longer exists");
        }
        return entity;
    }

    private void audit(Long caseId, String action, String details) {
        caseRepository.logAudit(new CaseAuditEntry(
                caseId, "explanation_state", null, action, SYSTEM_USER, action, details));
    }

    private static String truncate(String reason) {
        String safe = Objects.toString(reason, "unknown");
        return safe.length() <= 500 ? safe : safe.substring(0, 500) + "…";
    }
}
