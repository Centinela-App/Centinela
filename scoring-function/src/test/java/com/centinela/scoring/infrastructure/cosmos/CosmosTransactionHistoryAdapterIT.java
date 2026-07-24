package com.centinela.scoring.infrastructure.cosmos;

import com.azure.cosmos.CosmosClient;
import com.azure.cosmos.CosmosClientBuilder;
import com.azure.cosmos.CosmosContainer;
import com.azure.cosmos.models.PartitionKey;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.centinela.scoring.domain.model.HistoricalTransaction;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import java.math.BigDecimal;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * TEST-S2-009: verifica contra un Cosmos real que el historial de una cuenta
 * se recupera consultando una unica particion ({@code accountId}).
 *
 * <p>Protegida con {@code CENTINELA_RUN_AZURE_IT}: se omite sin suscripcion
 * de Azure (igual que las demas IT del proyecto).
 */
@EnabledIfEnvironmentVariable(named = "CENTINELA_RUN_AZURE_IT", matches = "(?i)true")
class CosmosTransactionHistoryAdapterIT {

    private static CosmosClient client;
    private static CosmosContainer container;
    private static final String ACCOUNT_ID = "it-account-" + UUID.randomUUID();

    @BeforeAll
    static void setUpContainer() {
        String endpoint = requiredEnvironment("CENTINELA_COSMOS_ENDPOINT");
        String database = requiredEnvironment("CENTINELA_COSMOS_DATABASE");
        String containerName = requiredEnvironment("CENTINELA_COSMOS_TRANSACTIONS_CONTAINER");

        client = new CosmosClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
        container = client.getDatabase(database).getContainer(containerName);

        seedTransaction("it-tx-1", OffsetDateTime.now().minusMinutes(30));
        seedTransaction("it-tx-2", OffsetDateTime.now().minusMinutes(10));
    }

    @AfterAll
    static void tearDown() {
        try {
            container.deleteItem("it-tx-1", new PartitionKey(ACCOUNT_ID), null);
            container.deleteItem("it-tx-2", new PartitionKey(ACCOUNT_ID), null);
        } finally {
            if (client != null) {
                client.close();
            }
        }
    }

    @Test
    void should_read_only_the_target_account_partition() {
        CosmosTransactionHistoryAdapter adapter = new CosmosTransactionHistoryAdapter(container);

        List<HistoricalTransaction> history = adapter.recentHistory(ACCOUNT_ID, OffsetDateTime.now());

        assertEquals(2, history.size());
        assertTrue(history.stream().allMatch(tx -> tx.transactionId().startsWith("it-tx-")));
    }

    private static void seedTransaction(String transactionId, OffsetDateTime occurredAt) {
        Map<String, Object> document = new LinkedHashMap<>();
        document.put("id", transactionId);
        document.put("transactionId", transactionId);
        document.put("accountId", ACCOUNT_ID);
        document.put("amount", new BigDecimal("42.00"));
        document.put("occurredAt", occurredAt.toString());
        document.put("location", Map.of("latitude", new BigDecimal("6.25"), "longitude", new BigDecimal("-75.56")));
        container.upsertItem(document, new PartitionKey(ACCOUNT_ID), null);
    }

    private static String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Missing required environment variable: " + name);
        }
        return value;
    }
}
