package com.centinela.casemanagement.application.port.out;

import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import com.centinela.casemanagement.domain.model.Case_;

import java.util.Optional;

/** Puerto de persistencia de casos. */
public interface CaseRepositoryPort {
    Optional<Case_> findByTransactionId(String transactionId);
    Case_ saveCaseWithAudit(Case_ case_, CaseAuditEntry auditEntry);
}
