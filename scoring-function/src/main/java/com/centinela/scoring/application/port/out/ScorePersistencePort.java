package com.centinela.scoring.application.port.out;

import com.centinela.scoring.domain.model.Score;
import com.centinela.scoring.domain.model.TransactionEvent;

/** Persiste de forma idempotente la transaccion y su score en Cosmos DB for MongoDB. */
@FunctionalInterface
public interface ScorePersistencePort {
    void persistScore(TransactionEvent transaction, Score score);
}
