package com.centinela.casemanagement.application.port.in;

import com.centinela.casemanagement.domain.model.Case_;
import com.centinela.casemanagement.domain.model.FlaggedCaseMessage;

/**
 * Puerto de entrada para abrir un caso a partir de un mensaje flagged.
 *
 * <p>Define el caso de uso de crear/abrir un caso cuando el motor de scoring
 * detecta una transacción sospechosa y la coloca en la cola.
 *
 * <p>La implementación debe ser idempotente: si el mismo mensaje se procesa
 * dos veces (reintentos de la cola), no debe crear casos duplicados.
 */
public interface OpenCaseUseCase {

    /**
     * Procesa un mensaje flagged y abre un caso.
     *
     * <p>Este método es idempotente respecto al transactionId del mensaje.
     * Si ya existe un caso para ese transactionId, devuelve el caso existente
     * sin crear uno nuevo.
     *
     * @param message el mensaje recibido de la cola de casos
     * @return el caso creado o existente
     * @throws IllegalArgumentException si message es null
     */
    Case_ openCase(FlaggedCaseMessage message);
}
