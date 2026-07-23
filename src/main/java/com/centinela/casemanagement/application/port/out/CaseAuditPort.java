package com.centinela.casemanagement.application.port.out;

import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;

/**
 * Puerto de salida: Auditoría de casos.
 * Arquitectura hexagonal - Puerto de salida (driven adapter).
 * Historia: HU-S2-001 · Criterio: Auditoría inmutable (append-only)
 */
@Repository
public interface CaseAuditPort extends JpaRepository<CaseAuditEntry, Long> {

    /**
     * Obtiene el historial de auditoría para un caso.
     */
    List<CaseAuditEntry> findByCaseIdOrderByChangedAtAsc(Long caseId);

    /**
     * Cuenta el número de entradas de auditoría para un caso.
     */
    long countByCaseId(Long caseId);
}
