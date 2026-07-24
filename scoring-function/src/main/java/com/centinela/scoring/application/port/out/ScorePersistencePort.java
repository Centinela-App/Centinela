package com.centinela.scoring.application.port.out;

import com.centinela.scoring.domain.model.Score;

/**
 * Puerto de salida para persistir el score junto a la transaccion en Cosmos.
 *
 * <p>La persistencia se realiza en la misma particion (accountId) que la transaccion
 * para optimizar consultas por cuenta. La idempotencia se garantiza usando
 * transactionId como clave de documento.
 */
@FunctionalInterface
public interface ScorePersistencePort {

    /**
     * Persiste el score junto a la transaccion usando la misma particion accountId.
     *
     * <p>Implementaciones deben ser idempotentes: re-procesar el mismo evento
     * no debe duplicar el score.
     *
     * @param score el resultado del scoring a persistir
     * @throws com.centinela.scoring.application.exception.ScorePersistenceException si la persistencia falla
     */
    void persistScore(Score score);
}
