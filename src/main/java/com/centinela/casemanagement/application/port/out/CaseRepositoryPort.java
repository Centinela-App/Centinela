package com.centinela.casemanagement.application.port.out;

import java.util.Optional;

import com.centinela.casemanagement.domain.model.CaseAuditEntry;
import com.centinela.casemanagement.domain.model.Case_;

/**
 * Puerto de salida para persistencia de casos.
 *
 * <p>Define las operaciones de escritura necesarias para el caso de uso
 * de apertura de casos.
 */
public interface CaseRepositoryPort {

    /**
     * Busca un caso por su identificador de transacción origen.
     *
     * @param transactionId el ID de la transacción que originó el caso
     * @return el caso si existe, vacío si no
     */
    Optional<Case_> findByTransactionId(String transactionId);

    /**
     * Guarda un caso y su entrada de auditoría de apertura en una transacción.
     *
     * <p>Ambos elementos deben guardarse atomicamente. Si la transacción falla,
     * ninguno de los dos debe persistirse.
     *
     * @param case_ el caso a guardar
     * @param auditEntry la entrada de auditoría de apertura
     */
    void saveCaseWithAudit(Case_ case_, CaseAuditEntry auditEntry);
}
