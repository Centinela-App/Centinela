package com.centinela.scoring.infrastructure.mongo;

import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import com.mongodb.client.MongoCollection;
import org.bson.Document;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.Date;
import java.util.List;
import java.util.UUID;

import static com.mongodb.client.model.Filters.eq;
import static org.assertj.core.api.Assertions.assertThat;

@EnabledIfEnvironmentVariable(named = "CENTINELA_RUN_AZURE_IT", matches = "(?i)true")
class CosmosMongoTransactionHistoryAdapterIT {
    private static MongoClient client;
    private static MongoCollection<Document> collection;
    private static final String ACCOUNT_ID = "it-account-" + UUID.randomUUID();

    @BeforeAll
    static void setUp() {
        client = MongoClients.create(required("CENTINELA_COSMOS_CONNECTION_STRING"));
        collection = client.getDatabase(required("CENTINELA_COSMOS_DATABASE"))
                .getCollection(required("CENTINELA_COSMOS_COLLECTION"));
        seed("it-tx-1", OffsetDateTime.now().minusMinutes(30));
        seed("it-tx-2", OffsetDateTime.now().minusMinutes(10));
    }

    @AfterAll
    static void tearDown() {
        if (collection != null) collection.deleteMany(eq("accountId", ACCOUNT_ID));
        if (client != null) client.close();
    }

    @Test
    void reads_history_using_account_id_in_the_targeted_filter() {
        List<HistoricalTransaction> history =
                new CosmosMongoTransactionHistoryAdapter(collection).recentHistory(ACCOUNT_ID, OffsetDateTime.now());

        assertThat(history).hasSize(2)
                .allMatch(transaction -> transaction.transactionId().startsWith("it-tx-"));
    }

    private static void seed(String transactionId, OffsetDateTime occurredAt) {
        collection.insertOne(new Document()
                .append("transactionId", transactionId)
                .append("accountId", ACCOUNT_ID)
                .append("amount", new BigDecimal("42.00"))
                .append("occurredAt", Date.from(occurredAt.toInstant()))
                .append("location", new Document("latitude", new BigDecimal("4.71"))
                        .append("longitude", new BigDecimal("-74.07"))));
    }

    private static String required(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) throw new IllegalStateException("Missing " + name);
        return value;
    }
}
