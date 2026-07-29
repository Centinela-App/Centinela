package com.centinela.scoringrecord.application.port.out;

import com.centinela.scoringrecord.domain.model.ScoringDecision;

import java.util.Optional;

/**
 * Lectura del registro que dejo el motor de scoring al decidir.
 *
 * <p>Vive en el almacen de transacciones (Cosmos), no en el mensaje de cola: el contrato
 * {@code flagged-case-v1} transporta solo un resumen — regla y puntos — mientras que los
 * valores observados que hacen posible la explicacion quedan junto a la transaccion.
 */
public interface ScoringDecisionReaderPort {

    /**
     * @return la decision registrada, o vacio si la transaccion no existe en el almacen o
     *         no tiene score persistido
     */
    Optional<ScoringDecision> findByTransactionId(String transactionId);
}
