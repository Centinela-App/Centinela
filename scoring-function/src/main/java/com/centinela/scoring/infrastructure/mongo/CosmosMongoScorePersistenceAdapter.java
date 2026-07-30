package com.centinela.scoring.infrastructure.mongo;

import com.centinela.scoring.application.exception.ScorePersistenceException;
import com.centinela.scoring.application.port.out.ScorePersistencePort;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.Score;
import com.centinela.scoring.domain.model.TransactionEvent;
import com.mongodb.client.MongoCollection;
import com.mongodb.client.model.ReplaceOptions;
import org.bson.Document;

import java.util.Date;
import java.util.Objects;

import static com.mongodb.client.model.Filters.and;
import static com.mongodb.client.model.Filters.eq;

/**
 * Upsert idempotente de la transaccion y su score en la misma shard {@code accountId}.
 *
 * <p>Este documento es la <b>unica fuente</b> del explicador de casos: el mensaje de cola
 * transporta solo un resumen (regla y puntos), mientras que los valores observados que
 * activaron cada regla viven aqui. Si un dato no se escribe en este punto, el explicador
 * no puede recuperarlo despues sin reprocesar la transaccion.
 */
public final class CosmosMongoScorePersistenceAdapter implements ScorePersistencePort {
    private final MongoCollection<Document> collection;

    public CosmosMongoScorePersistenceAdapter(MongoCollection<Document> collection) {
        this.collection = Objects.requireNonNull(collection, "collection is required");
    }

    @Override
    public void persistScore(TransactionEvent transaction, Score score) {
        try {
            Document document = new Document()
                    .append("transactionId", transaction.transactionId())
                    .append("accountId", transaction.accountId())
                    .append("amount", transaction.amount())
                    .append("currency", transaction.currency())
                    .append("occurredAt", Date.from(transaction.occurredAt().toInstant()))
                    .append("traceparent", score.traceparent())
                    .append("location", new Document()
                            .append("countryCode", transaction.location().countryCode())
                            .append("city", transaction.location().city())
                            .append("latitude", transaction.location().latitude())
                            .append("longitude", transaction.location().longitude()))
                    .append("merchant", new Document()
                            .append("name", transaction.merchant().name())
                            .append("category", transaction.merchant().category()))
                    .append("score", new Document()
                            .append("total", score.totalScore())
                            .append("threshold", score.threshold())
                            .append("flagged", score.isFlagged())
                            .append("scoredAt", Date.from(score.scoredAt()))
                            .append("triggeredRules", score.triggeredRules().stream()
                                    .map(CosmosMongoScorePersistenceAdapter::ruleDocument)
                                    .toList()));

            collection.replaceOne(
                    and(eq("accountId", transaction.accountId()),
                            eq("transactionId", transaction.transactionId())),
                    document,
                    new ReplaceOptions().upsert(true));
        } catch (RuntimeException exception) {
            throw new ScorePersistenceException(
                    "Failed to persist score for transaction " + score.transactionId(), exception);
        }
    }

    private static Document ruleDocument(RuleHit hit) {
        return new Document()
                .append("ruleId", hit.ruleId())
                .append("ruleName", hit.ruleName())
                .append("points", hit.points())
                .append("observedValues", new Document(hit.observedValues()));
    }
}
