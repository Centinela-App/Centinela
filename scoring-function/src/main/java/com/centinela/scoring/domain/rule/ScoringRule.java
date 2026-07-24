package com.centinela.scoring.domain.rule;

import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.TransactionEvent;

import java.util.List;
import java.util.Optional;

/**
 * Contrato de una regla pura de dominio para el motor de scoring.
 *
 * <p>Toda regla evalua la transaccion actual y el historial de la cuenta,
 * devolviendo un {@link RuleHit} con los puntos asignados y los valores observados
 * si la regla se activa.
 */
public interface ScoringRule {

    /**
     * Identificador unico de la regla.
     */
    String ruleId();

    /**
     * Evalua la transaccion actual contra el historial de la cuenta.
     *
     * @param transaction transaccion actual a puntuar
     * @param history historial reciente de transacciones de la misma cuenta
     * @return {@link Optional} con el {@link RuleHit} si la regla se activo, o vacio si no.
     */
    Optional<RuleHit> evaluate(TransactionEvent transaction, List<HistoricalTransaction> history);
}
