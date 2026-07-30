package com.centinela.casemanagement.application.port.out;

import com.centinela.casemanagement.domain.model.CaseAuditEntry;

import java.util.List;

/** Puerto de consulta append-only de auditoria. */
public interface CaseAuditPort {
    List<CaseAuditEntry> findByCaseIdOrderByChangedAtAsc(Long caseId);
    long countByCaseId(Long caseId);
}
