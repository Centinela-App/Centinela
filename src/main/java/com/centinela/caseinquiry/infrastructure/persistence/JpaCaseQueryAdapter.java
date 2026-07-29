package com.centinela.caseinquiry.infrastructure.persistence;

import com.centinela.caseinquiry.application.port.out.CaseQueryPort;
import com.centinela.caseinquiry.domain.model.CaseView;
import com.centinela.caseinquiry.domain.model.VerificationDocumentView;
import com.centinela.casemanagement.domain.model.FraudCase;
import com.centinela.documentverification.infrastructure.persistence.CaseVerificationDocumentEntity;
import jakarta.persistence.EntityManager;
import jakarta.persistence.NoResultException;
import jakarta.persistence.PersistenceContext;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

/** Lectura JPA del caso y de los documentos que se le adjuntaron. */
@Component
public class JpaCaseQueryAdapter implements CaseQueryPort {

    @PersistenceContext
    private EntityManager entityManager;

    @Override
    @Transactional(readOnly = true)
    public Optional<CaseView> findByTransactionId(String transactionId) {
        FraudCase entity;
        try {
            entity = entityManager.createQuery(
                            "SELECT c FROM FraudCase c WHERE c.transactionId = :transactionId",
                            FraudCase.class)
                    .setParameter("transactionId", transactionId)
                    .getSingleResult();
        } catch (NoResultException exception) {
            return Optional.empty();
        }

        return Optional.of(new CaseView(
                entity.getId(),
                entity.getTransactionId(),
                entity.getAccountId(),
                entity.getScore(),
                entity.getStateCode(),
                entity.getExplanationState(),
                entity.getExplanation(),
                entity.getTraceparent(),
                entity.getOpenedAt(),
                entity.getUpdatedAt(),
                documentsOf(entity.getId())));
    }

    private List<VerificationDocumentView> documentsOf(Long caseId) {
        return entityManager.createQuery(
                        "SELECT d FROM CaseVerificationDocumentEntity d "
                                + "WHERE d.caseId = :caseId ORDER BY d.receivedAt ASC",
                        CaseVerificationDocumentEntity.class)
                .setParameter("caseId", caseId)
                .getResultList()
                .stream()
                .map(JpaCaseQueryAdapter::toView)
                .toList();
    }

    private static VerificationDocumentView toView(CaseVerificationDocumentEntity entity) {
        return new VerificationDocumentView(
                entity.getId(),
                entity.getBlobPath(),
                entity.getContentType(),
                entity.getDocumentState(),
                entity.getExtractedFullName(),
                entity.getExtractedDocumentNumber(),
                entity.getExtractedBirthDate(),
                entity.getExtractedExpiryDate(),
                entity.getExtractionEngine(),
                entity.getFailureReason(),
                entity.getReceivedAt(),
                entity.getProcessedAt(),
                entity.getAnalystNotifiedAt());
    }
}
