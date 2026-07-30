package com.centinela.documentverification.infrastructure.persistence;

import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import com.centinela.casemanagement.infrastructure.persistence.JpaCaseRepositoryAdapter;
import com.centinela.documentverification.application.port.out.VerificationDocumentRegistryPort;
import com.centinela.documentverification.domain.model.DocumentState;
import com.centinela.documentverification.domain.model.ExtractionOutcome;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import jakarta.transaction.Transactional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.List;
import java.util.Objects;
import java.util.Optional;

/** Adaptador JPA sobre {@code case_verification_document}. */
@Component
public class JpaVerificationDocumentRegistryAdapter implements VerificationDocumentRegistryPort {

    private static final Logger log = LoggerFactory.getLogger(JpaVerificationDocumentRegistryAdapter.class);
    private static final String SYSTEM_USER = "system:document-verification";

    @PersistenceContext
    private EntityManager entityManager;

    private final JpaCaseRepositoryAdapter caseRepository;

    public JpaVerificationDocumentRegistryAdapter(JpaCaseRepositoryAdapter caseRepository) {
        this.caseRepository = Objects.requireNonNull(caseRepository, "caseRepository is required");
    }

    @Override
    @Transactional
    public Optional<Long> registerReceived(
            String transactionId, String blobPath, String contentType, Instant receivedAt) {

        Optional<Long> caseId = caseRepository.findByTransactionId(transactionId)
                .map(existing -> existing.caseId());

        if (caseId.isEmpty()) {
            // Documento cargado para una transaccion sin caso abierto. No es un error del
            // analista ni motivo para rechazar la carga: el archivo ya esta guardado en el
            // contenedor. Simplemente no hay caso al que adjuntarlo.
            log.warn("Verification document {} has no case for transaction {}", blobPath, transactionId);
            return Optional.empty();
        }

        CaseVerificationDocumentEntity entity =
                new CaseVerificationDocumentEntity(caseId.get(), blobPath, contentType, receivedAt);
        entityManager.persist(entity);
        entityManager.flush();

        caseRepository.logAudit(new CaseAuditEntry(
                caseId.get(), "verification_document", null, DocumentState.RECEIVED.name(),
                SYSTEM_USER, "DOCUMENT_RECEIVED", "blobPath=" + blobPath));

        return Optional.of(entity.getId());
    }

    @Override
    public List<PendingDocument> findPending(int limit) {
        return entityManager.createQuery(
                        "SELECT d FROM CaseVerificationDocumentEntity d "
                                + "WHERE d.documentState = :state ORDER BY d.receivedAt ASC",
                        CaseVerificationDocumentEntity.class)
                .setParameter("state", DocumentState.RECEIVED.name())
                .setMaxResults(limit)
                .getResultList()
                .stream()
                .map(entity -> new PendingDocument(
                        entity.getId(), entity.getCaseId(), entity.getBlobPath(), entity.getContentType()))
                .toList();
    }

    /**
     * Escribe el desenlace y notifica al analista de forma atomica.
     *
     * <p>La notificacion se materializa como una entrada en la bitacora inmutable del caso,
     * que es lo que el analista consulta. El envio por correo o mensajeria queda fuera del
     * alcance del proyecto y se documenta como tal: lo que el requisito exige es que el
     * analista <b>reciba el resultado</b>, no un canal concreto.
     */
    @Override
    @Transactional
    public void recordOutcome(Long documentId, ExtractionOutcome outcome, Instant processedAt) {
        CaseVerificationDocumentEntity entity =
                entityManager.find(CaseVerificationDocumentEntity.class, documentId);
        if (entity == null) {
            throw new IllegalStateException("Verification document " + documentId + " no longer exists");
        }

        entity.applyOutcome(outcome, processedAt);
        entityManager.merge(entity);

        caseRepository.logAudit(new CaseAuditEntry(
                entity.getCaseId(),
                "verification_document",
                DocumentState.RECEIVED.name(),
                outcome.state().name(),
                SYSTEM_USER,
                "DOCUMENT_" + outcome.state().name(),
                outcome.analystMessage(entity.getBlobPath())));

        entityManager.flush();
    }
}
