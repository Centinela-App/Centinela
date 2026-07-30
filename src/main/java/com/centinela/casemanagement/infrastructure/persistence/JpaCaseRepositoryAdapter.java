package com.centinela.casemanagement.infrastructure.persistence;

import com.centinela.casemanagement.application.port.out.CaseAuditPort;
import com.centinela.casemanagement.application.port.out.CaseRepositoryPort;
import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import com.centinela.casemanagement.domain.model.Case_;
import com.centinela.casemanagement.domain.model.FraudCase;
import jakarta.persistence.EntityManager;
import jakarta.persistence.NoResultException;
import jakarta.persistence.PersistenceContext;
import jakarta.transaction.Transactional;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Optional;

/** Adaptador JPA único para el modelo relacional definido por Flyway. */
@Component
public class JpaCaseRepositoryAdapter implements CaseRepositoryPort, CaseAuditPort {

    @PersistenceContext
    private EntityManager entityManager;

    @Override
    public Optional<Case_> findByTransactionId(String transactionId) {
        return findFraudCaseByTransactionId(transactionId).map(FraudCase::toDomain);
    }

    @Override
    @Transactional
    public Case_ saveCaseWithAudit(Case_ case_, CaseAuditEntry auditEntry) {
        FraudCase entity = FraudCase.fromDomain(case_);
        entityManager.persist(entity);
        entityManager.flush();

        auditEntry.assignCaseId(entity.getId());
        CaseAuditEntity auditEntity = CaseAuditEntity.fromDomain(auditEntry);
        entityManager.persist(auditEntity);
        entityManager.flush();
        return entity.toDomain();
    }

    @Transactional
    public FraudCase save(FraudCase fraudCase) {
        if (fraudCase.getId() == null) {
            entityManager.persist(fraudCase);
            entityManager.flush();
            return fraudCase;
        }
        return entityManager.merge(fraudCase);
    }

    public Optional<FraudCase> findById(Long id) {
        return Optional.ofNullable(entityManager.find(FraudCase.class, id));
    }

    public boolean existsByTransactionId(String transactionId) {
        return findFraudCaseByTransactionId(transactionId).isPresent();
    }

    @Transactional
    public CaseAuditEntry logAudit(CaseAuditEntry entry) {
        CaseAuditEntity entity = CaseAuditEntity.fromDomain(entry);
        entityManager.persist(entity);
        entityManager.flush();
        return entity.toDomain();
    }

    @Override
    public List<CaseAuditEntry> findByCaseIdOrderByChangedAtAsc(Long caseId) {
        return entityManager.createQuery(
                        "SELECT a FROM CaseAuditEntity a WHERE a.caseId = :caseId ORDER BY a.changedAt ASC",
                        CaseAuditEntity.class)
                .setParameter("caseId", caseId)
                .getResultList()
                .stream()
                .map(CaseAuditEntity::toDomain)
                .toList();
    }

    public List<CaseAuditEntry> findAuditByCaseId(Long caseId) {
        return findByCaseIdOrderByChangedAtAsc(caseId);
    }

    @Override
    public long countByCaseId(Long caseId) {
        return entityManager.createQuery(
                        "SELECT COUNT(a) FROM CaseAuditEntity a WHERE a.caseId = :caseId", Long.class)
                .setParameter("caseId", caseId)
                .getSingleResult();
    }

    private Optional<FraudCase> findFraudCaseByTransactionId(String transactionId) {
        try {
            FraudCase entity = entityManager.createQuery(
                            "SELECT c FROM FraudCase c WHERE c.transactionId = :transactionId",
                            FraudCase.class)
                    .setParameter("transactionId", transactionId)
                    .getSingleResult();
            return Optional.of(entity);
        } catch (NoResultException exception) {
            return Optional.empty();
        }
    }
}
