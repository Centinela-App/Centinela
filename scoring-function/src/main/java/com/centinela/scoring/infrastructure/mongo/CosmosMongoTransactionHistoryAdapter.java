package com.centinela.scoring.infrastructure.mongo;

import com.centinela.scoring.application.port.out.TransactionHistoryPort;
import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.mongodb.client.MongoCollection;
import org.bson.Document;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Date;
import java.util.ArrayList;
import java.util.List;
import java.util.Objects;
import java.util.logging.Logger;

import static com.mongodb.client.model.Filters.and;
import static com.mongodb.client.model.Filters.eq;
import static com.mongodb.client.model.Filters.lt;
import static com.mongodb.client.model.Projections.excludeId;
import static com.mongodb.client.model.Projections.fields;
import static com.mongodb.client.model.Projections.include;
import static com.mongodb.client.model.Sorts.descending;

/** Consulta dirigida por la shard key {@code accountId} en Cosmos DB for MongoDB. */
public final class CosmosMongoTransactionHistoryAdapter implements TransactionHistoryPort {
    private static final Logger LOGGER = Logger.getLogger(CosmosMongoTransactionHistoryAdapter.class.getName());
    private static final int DEFAULT_LIMIT = 50;

    private final MongoCollection<Document> collection;
    private final int historyLimit;

    public CosmosMongoTransactionHistoryAdapter(MongoCollection<Document> collection) {
        this(collection, DEFAULT_LIMIT);
    }

    public CosmosMongoTransactionHistoryAdapter(MongoCollection<Document> collection, int historyLimit) {
        this.collection = Objects.requireNonNull(collection, "collection is required");
        if (historyLimit <= 0) throw new IllegalArgumentException("historyLimit must be positive");
        this.historyLimit = historyLimit;
    }

    @Override
    public List<HistoricalTransaction> recentHistory(String accountId, OffsetDateTime before) {
        Objects.requireNonNull(accountId, "accountId is required");
        Objects.requireNonNull(before, "before is required");

        List<HistoricalTransaction> result = new ArrayList<>();
        collection.find(and(eq("accountId", accountId), lt("occurredAt", Date.from(before.toInstant()))))
                .projection(fields(include("transactionId", "amount", "occurredAt", "location"), excludeId()))
                .sort(descending("occurredAt"))
                .limit(historyLimit)
                .forEach(document -> result.add(toDomain(document)));

        LOGGER.info(() -> "cosmosMongo.targetedQuery shardKey=accountId accountId="
                + accountId + " results=" + result.size());
        return List.copyOf(result);
    }

    private static HistoricalTransaction toDomain(Document document) {
        Document location = document.get("location", Document.class);
        return new HistoricalTransaction(
                document.getString("transactionId"),
                decimal(document.get("amount")),
                occurredAt(document.get("occurredAt")),
                location == null ? null : decimal(location.get("latitude")),
                location == null ? null : decimal(location.get("longitude")));
    }

    private static OffsetDateTime occurredAt(Object value) {
        if (value instanceof Date date) {
            return OffsetDateTime.ofInstant(date.toInstant(), ZoneOffset.UTC);
        }
        if (value instanceof String text) {
            return OffsetDateTime.parse(text);
        }
        throw new IllegalArgumentException("occurredAt must be a BSON date or RFC 3339 string");
    }

    private static BigDecimal decimal(Object value) {
        if (value == null) return null;
        if (value instanceof BigDecimal decimal) return decimal;
        if (value instanceof Number number) return new BigDecimal(number.toString());
        return new BigDecimal(value.toString());
    }
}
