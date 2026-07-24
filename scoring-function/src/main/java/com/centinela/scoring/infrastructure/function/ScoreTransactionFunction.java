package com.centinela.scoring.infrastructure.function;

import com.azure.cosmos.CosmosClient;
import com.azure.cosmos.CosmosClientBuilder;
import com.azure.cosmos.CosmosContainer;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.centinela.scoring.application.port.out.TransactionHistoryPort;
import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.centinela.scoring.domain.model.TransactionEvent;
import com.centinela.scoring.infrastructure.cosmos.CosmosTransactionHistoryAdapter;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.annotation.EventGridTrigger;
import com.microsoft.azure.functions.annotation.FunctionName;

import java.util.List;
import java.util.logging.Level;

/**
 * ISS-S2-007: se activa por Event Grid ({@code transaction-event-v1}) y
 * SOLO recupera el historial de la cuenta desde una unica particion de
 * Cosmos, registrando la evidencia de RU. Aun sin reglas de deteccion
 * (ISS-S2-008) ni persistencia/publicacion (ISS-S2-009): eso llega en las
 * siguientes issues, que reemplazaran esta clase.
 *
 * <p>Fuera de alcance (y por tanto ausente de este archivo): reglas de
 * umbral, invocacion sincrona desde la API.
 */
public final class ScoreTransactionFunction {

    private static volatile TransactionHistoryPort historyPort;
    private static final Object INIT_LOCK = new Object();

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper()
            .registerModule(new JavaTimeModule())
            .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    @FunctionName("ScoreTransaction")
    public void run(
            @EventGridTrigger(name = "event") String eventPayload,
            ExecutionContext context) {
        try {
            com.fasterxml.jackson.databind.JsonNode rootNode = OBJECT_MAPPER.readTree(eventPayload);
            com.fasterxml.jackson.databind.JsonNode dataNode = rootNode.has("data") ? rootNode.get("data") : rootNode;
            TransactionEvent transaction = OBJECT_MAPPER.treeToValue(dataNode, TransactionEvent.class);

            context.getLogger().info(
                    "transaction-event-v1 received, accountId=" + transaction.accountId()
                            + " transactionId=" + transaction.transactionId());

            List<HistoricalTransaction> history = historyPort()
                    .recentHistory(transaction.accountId(), transaction.occurredAt());

            // Evidencia pedida por TEST-S2-009: confirma la activacion y el tamano
            // del historial recuperado. El RU/consumo de la consulta ya queda
            // registrado dentro de CosmosTransactionHistoryAdapter.
            context.getLogger().info(
                    "history retrieved accountId=" + transaction.accountId()
                            + " historySize=" + history.size());
        } catch (Exception exception) {
            context.getLogger().log(Level.SEVERE, "Failed to process transaction-event-v1", exception);
            throw new RuntimeException("Failed to process transaction-event-v1", exception);
        }
    }

    private static TransactionHistoryPort historyPort() {
        TransactionHistoryPort current = historyPort;
        if (current == null) {
            synchronized (INIT_LOCK) {
                current = historyPort;
                if (current == null) {
                    current = buildHistoryPort();
                    historyPort = current;
                }
            }
        }
        return current;
    }

    private static TransactionHistoryPort buildHistoryPort() {
        CosmosClient cosmosClient;
        String keyVaultUri = System.getenv("KEY_VAULT_URI");
        if (keyVaultUri != null && !keyVaultUri.isBlank()) {
            com.centinela.scoring.infrastructure.config.KeyVaultConnectionStrings keyVault =
                    new com.centinela.scoring.infrastructure.config.KeyVaultConnectionStrings();
            String connString = keyVault.cosmosConnectionString();
            CosmosClientBuilder builder = new CosmosClientBuilder();
            String endpoint = null;
            String key = null;
            for (String part : connString.split(";")) {
                if (part.startsWith("AccountEndpoint=")) {
                    endpoint = part.substring("AccountEndpoint=".length());
                } else if (part.startsWith("AccountKey=")) {
                    key = part.substring("AccountKey=".length());
                }
            }
            if (endpoint != null) {
                builder.endpoint(endpoint);
            }
            if (key != null && !key.isBlank()) {
                builder.key(key);
            } else {
                builder.credential(new DefaultAzureCredentialBuilder().build());
            }
            cosmosClient = builder.buildClient();
        } else {
            String endpoint = requiredEnv("COSMOS_ENDPOINT");
            cosmosClient = new CosmosClientBuilder()
                    .endpoint(endpoint)
                    .credential(new DefaultAzureCredentialBuilder().build())
                    .buildClient();
        }
        CosmosContainer container = cosmosClient
                .getDatabase(requiredEnv("COSMOS_DATABASE"))
                .getContainer(requiredEnv("COSMOS_TRANSACTIONS_CONTAINER"));
        return new CosmosTransactionHistoryAdapter(container);
    }

    private static String requiredEnv(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Missing required App Setting: " + name);
        }
        return value;
    }
}
