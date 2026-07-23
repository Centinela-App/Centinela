package com.centinela.casemanagement.infrastructure.persistence;

import com.centinela.casemanagement.application.port.out.CaseRepositoryPort;
import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import com.centinela.casemanagement.domain.model.Case_;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import jakarta.transaction.Transactional;
import org.springframework.stereotype.Component;

import java.util.Optional;

/**
 * Implementación del puerto de salida CaseRepositoryPort usando JPA.
 *
 * <p>Persiste casos y entradas de auditoría de forma atómica en la misma
 * transacción de base de datos.
 */
@Component
public class JpaCaseRepositoryAdapter implements CaseRepositoryPort {

    @PersistenceContext
    private EntityManager entityManager;

    @Override
    public Optional<Case_> findByTransactionId(String transactionId) {
        // Busca en la tabla fraud_cases por transactionId
        try {
            var query = entityManager.createQuery(
                    "SELECT c FROM FraudCaseEntity c WHERE c.transactionId = :transactionId",
                    FraudCaseEntity.class);
            query.setParameter("transactionId", transactionId);
            var entity = query.getSingleResult();
            return Optional.of(entity.toDomain());
        } catch (jakarta.persistence.NoResultException e) {
            return Optional.empty();
        }
    }

    @Override
    @Transactional
    public void saveCaseWithAudit(Case_ case_, CaseAuditEntry auditEntry) {
        // Persistir el caso y la auditoría en la misma transacción
        entityManager.persist(auditEntry);
        entityManager.flush();

        // Crear entidad de caso desde el record Case_
        FraudCaseEntity caseEntity = FraudCaseEntity.fromDomain(case_);
        entityManager.persist(caseEntity);
        entityManager.flush();
    }
}
