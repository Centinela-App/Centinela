package com.centinela.casemanagement.infrastructure.persistence;

import com.centinela.casemanagement.application.port.out.CaseAuditPort;
import com.centinela.casemanagement.application.port.out.CaseRepositoryPort;
import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import com.centinela.casemanagement.domain.model.FraudCase;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

/**
 * Adaptador de infraestructura: Implementación de puertos JPA.
 * Arquitectura hexagonal - Adapter de persistencia.
 * Historia: HU-S2-001
 */
@Component
public class JpaCaseRepositoryAdapter {

    private final CaseRepositoryPort caseRepository;
    private final CaseAuditPort caseAudit;

    public JpaCaseRepositoryAdapter(CaseRepositoryPort caseRepository, CaseAuditPort caseAudit) {
        this.caseRepository = caseRepository;
        this.caseAudit = caseAudit;
    }

    // === CaseRepositoryPort ===

    public FraudCase save(FraudCase fraudCase) {
        return caseRepository.save(fraudCase);
    }

    public Optional<FraudCase> findById(Long id) {
        return caseRepository.findById(id);
    }

    public Optional<FraudCase> findByTransactionId(String transactionId) {
        return caseRepository.findByTransactionId(transactionId);
    }

    public boolean existsByTransactionId(String transactionId) {
        return caseRepository.existsByTransactionId(transactionId);
    }

    public List<FraudCase> findAll() {
        return caseRepository.findAll();
    }

    @Transactional
    public void delete(FraudCase fraudCase) {
        caseRepository.delete(fraudCase);
    }

    // === CaseAuditPort ===

    /**
     * Registra una entrada de auditoría.
     * Este método solo realiza INSERT; la BD rechaza UPDATE/DELETE.
     */
    public CaseAuditEntry logAudit(CaseAuditEntry entry) {
        return caseAudit.save(entry);
    }

    public List<CaseAuditEntry> findAuditByCaseId(Long caseId) {
        return caseAudit.findByCaseIdOrderByChangedAtAsc(caseId);
    }

    public long countAuditEntries(Long caseId) {
        return caseAudit.countByCaseId(caseId);
    }
}
