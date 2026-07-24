package com.centinela.scoring.infrastructure.config;

import com.azure.cosmos.CosmosClient;
import com.azure.cosmos.CosmosClientBuilder;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.queue.QueueClient;
import com.azure.storage.queue.QueueClientBuilder;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.centinela.scoring.application.port.out.FlaggedCasePublisherPort;
import com.centinela.scoring.application.port.out.ScorePersistencePort;
import com.centinela.scoring.application.service.ScoreTransactionService;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.Score;
import com.centinela.scoring.infrastructure.cosmos.CosmosScorePersistenceAdapter;
import com.centinela.scoring.infrastructure.queue.StorageQueueFlaggedCasePublisher;

import java.time.Clock;
import java.time.Instant;
import java.util.List;

/**
 * Configuracion manual de dependencias para Azure Functions.
 *
 * <p>En Azure Functions no hay contenedor IoC como Spring.
 * Creamos los objetos directamente usando el patron de configuracion.
 */
public final class ScoringConfiguration {

    private ScoringConfiguration() {}

    public static ObjectMapper createObjectMapper() {
        ObjectMapper mapper = new ObjectMapper();
        mapper.registerModule(new JavaTimeModule());
        return mapper;
    }

    public static Clock createClock() {
        return Clock.systemUTC();
    }

    public static int createScoringThreshold() {
        return Integer.parseInt(
                System.getenv().getOrDefault("SCORING_THRESHOLD", "50")
        );
    }

    public static CosmosClient createCosmosClient() {
        String endpoint = System.getenv("COSMOS_ENDPOINT");
        if (endpoint == null || endpoint.isBlank()) {
            throw new IllegalStateException("COSMOS_ENDPOINT environment variable is required");
        }

        // Usa DefaultAzureCredential para autenticarse con Managed Identity
        return new CosmosClientBuilder()
                .endpoint(endpoint)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
    }

    public static com.azure.cosmos.CosmosContainer createCosmosContainer(CosmosClient cosmosClient) {
        String databaseName = System.getenv().getOrDefault("COSMOS_DATABASE", "centinela");
        String collectionName = System.getenv().getOrDefault("COSMOS_COLLECTION", "transactions");

        return cosmosClient.getDatabase(databaseName).getContainer(collectionName);
    }

    public static QueueClient createFlaggedCasesQueueClient() {
        String connectionString = System.getenv("AZURE_STORAGE_CONNECTION_STRING");
        String queueName = System.getenv().getOrDefault("FLAGGED_CASES_QUEUE", "flagged-cases");

        if (connectionString == null || connectionString.isBlank()) {
            throw new IllegalStateException("AZURE_STORAGE_CONNECTION_STRING environment variable is required");
        }

        return new QueueClientBuilder()
                .connectionString(connectionString)
                .queueName(queueName)
                .buildClient();
    }

    public static ScorePersistencePort createScorePersistencePort(
            com.azure.cosmos.CosmosContainer container,
            ObjectMapper objectMapper) {
        return new CosmosScorePersistenceAdapter(container, objectMapper);
    }

    public static FlaggedCasePublisherPort createFlaggedCasePublisherPort(
            QueueClient queueClient,
            ObjectMapper objectMapper) {
        return new StorageQueueFlaggedCasePublisher(queueClient, objectMapper);
    }

    public static ScoreTransactionService createScoreTransactionService(
            ObjectMapper objectMapper,
            ScorePersistencePort scorePersistencePort,
            FlaggedCasePublisherPort flaggedCasePublisherPort) {
        
        return new ScoreTransactionService(
                new ScoreTransactionService.ScoreCalculationPort() {
                    @Override
                    public Score calculateScore(String transactionId, String accountId, Instant scoredAt) {
                        // Implementacion simple - en produccion vendria del motor de reglas
                        return new Score(
                                transactionId,
                                accountId,
                                25, // score fijo por ahora
                                List.of(
                                        new RuleHit("R001", "Prueba", 25, java.util.Map.of("test", "value"))
                                ),
                                scoredAt
                        );
                    }
                },
                scorePersistencePort,
                flaggedCasePublisherPort,
                createScoringThreshold(),
                createClock()
        );
    }
}
