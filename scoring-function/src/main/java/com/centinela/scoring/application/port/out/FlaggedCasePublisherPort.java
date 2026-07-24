package com.centinela.scoring.application.port.out;

import com.centinela.scoring.domain.model.Score;

/**
 * Puerto de salida para publicar un caso marcado (flagged-case-v1) en la cola de casos.
 *
 * <p>Este puerto solo se invoca cuando el score supera el umbral configurado.
 * La publicacion usa la cola para garantizar procesamiento asincrono y resiliente.
 */
@FunctionalInterface
public interface FlaggedCasePublisherPort {

    /**
     * Publica un mensaje de caso marcado en la cola de casos.
     *
     * <p>Este metodo solo debe invocarse cuando score >= umbral.
     * El mensaje sigue el esquema flagged-case-v1.
     *
     * @param score el score que supero el umbral
     * @throws com.centinela.scoring.application.exception.FlaggedCasePublishException si la publicacion falla
     */
    void publishFlaggedCase(Score score);
}
