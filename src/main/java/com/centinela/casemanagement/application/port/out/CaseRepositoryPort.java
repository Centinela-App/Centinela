package com.centinela.casemanagement.application.port.out;

import com.centinela.casemanagement.domain.model.FraudCase;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

/**
 * Puerto de salida: Repositorio de casos de fraude.
 * Arquitectura hexagonal - Puerto de salida (driven adapter).
 * Historia: HU-S2-001
 */
@Repository
public interface CaseRepositoryPort extends JpaRepository<FraudCase, Long> {

    /**
     * Busca un caso por el ID de transacción.
     */
    Optional<FraudCase> findByTransactionId(String transactionId);

    /**
     * Verifica si existe un caso para la transacción dada.
     */
    boolean existsByTransactionId(String transactionId);
}
