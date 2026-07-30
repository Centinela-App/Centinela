package com.centinela.scoring.infrastructure.function;

import com.azure.identity.DefaultAzureCredential;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobServiceClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.azure.storage.queue.QueueClient;
import com.azure.storage.queue.QueueClientBuilder;
import com.centinela.scoring.application.config.ScoringThresholdProvider;
import com.centinela.scoring.application.port.out.RawTransactionReaderPort;
import com.centinela.scoring.application.port.out.TransactionHistoryPort;
import com.centinela.scoring.application.service.ScoreTransactionService;
import com.centinela.scoring.domain.model.HistoricalTransaction;
import com.centinela.scoring.domain.model.Score;
import com.centinela.scoring.domain.model.TransactionEvent;
import com.centinela.scoring.domain.model.TransactionEventNotification;
import com.centinela.scoring.infrastructure.blob.BlobRawTransactionReaderAdapter;
import com.centinela.scoring.infrastructure.config.KeyVaultConnectionStrings;
import com.centinela.scoring.infrastructure.mongo.CosmosMongoScorePersistenceAdapter;
import com.centinela.scoring.infrastructure.mongo.CosmosMongoTransactionHistoryAdapter;
import com.centinela.scoring.infrastructure.queue.StorageQueueFlaggedCasePublisher;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.microsoft.azure.functions.ExecutionContext;
import com.microsoft.azure.functions.annotation.EventGridTrigger;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import com.mongodb.client.MongoCollection;
import org.bson.Document;

import java.time.Clock;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.logging.Level;

/** Function integrada: contrato -> Blob -> historial Mongo -> reglas -> score -> cola. */
public final class ScoreTransactionFunction {
    private static final Object INIT_LOCK = new Object();
    private static volatile RuntimeDependencies runtime;

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper()
            .registerModule(new JavaTimeModule())
            .enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES)
            .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);

    @FunctionName("ScoreTransaction")
    public void run(
            @EventGridTrigger(name = "event") String eventPayload,
            ExecutionContext context) {
        long startedAtNanos = System.nanoTime();
        try {
            TransactionEventNotification notification = parseNotification(eventPayload);
            RuntimeDependencies dependencies = runtime();
            TransactionEvent transaction = dependencies.rawTransactionReader().read(notification);

            context.getLogger().info("transaction-event-v1 received accountId="
                    + notification.accountId() + " transactionId=" + notification.transactionId()
                    + " traceId=" + traceIdOf(notification.traceparent()));

            List<HistoricalTransaction> history = dependencies.historyPort()
                    .recentHistory(notification.accountId(), notification.occurredAt());
            Score score = dependencies.scoreServiceFor(notification)
                    .executeScoring(transaction, history, notification.traceparent());

            // Misma forma clave-valor que StageTelemetry en el modulo principal, para que
            // las consultas de operacion puedan unir las etapas de los dos procesos sin
            // expresiones regulares distintas por componente.
            context.getLogger().info("stage=SCORING"
                    + " transactionId=" + score.transactionId()
                    + " traceId=" + traceIdOf(score.traceparent())
                    + " durationMs=" + (System.nanoTime() - startedAtNanos) / 1_000_000
                    + " outcome=SUCCESS"
                    + " totalScore=" + score.totalScore()
                    + " threshold=" + score.threshold()
                    + " flagged=" + score.isFlagged()
                    + " triggeredRules=" + score.triggeredRules().size());
        } catch (Exception exception) {
            context.getLogger().log(Level.SEVERE, "stage=SCORING"
                    + " durationMs=" + (System.nanoTime() - startedAtNanos) / 1_000_000
                    + " outcome=FAILURE reason=\"" + exception.getMessage() + "\"", exception);
            throw new RuntimeException("Failed to process transaction-event-v1", exception);
        }
    }

    /** Extrae el {@code trace-id} del {@code traceparent} para correlacionar registros. */
    private static String traceIdOf(String traceparent) {
        return com.centinela.scoring.domain.model.TraceContext.parse(traceparent)
                .map(com.centinela.scoring.domain.model.TraceContext::traceId)
                .orElse("unknown");
    }

    private static TransactionEventNotification parseNotification(String eventPayload) throws Exception {
        JsonNode root = OBJECT_MAPPER.readTree(eventPayload);
        JsonNode data = root.has("data") ? root.get("data") : root;
        if (data.isTextual()) {
            data = OBJECT_MAPPER.readTree(data.asText());
        }
        return OBJECT_MAPPER.treeToValue(data, TransactionEventNotification.class);
    }

    private static RuntimeDependencies runtime() {
        RuntimeDependencies current = runtime;
        if (current == null) {
            synchronized (INIT_LOCK) {
                current = runtime;
                if (current == null) {
                    current = buildRuntime();
                    runtime = current;
                }
            }
        }
        return current;
    }

    private static RuntimeDependencies buildRuntime() {
        DefaultAzureCredential credential = new DefaultAzureCredentialBuilder().build();
        String storageAccount = requiredEnv("CENTINELA_STORAGE_ACCOUNT");
        String productionContainer = requiredEnv("CENTINELA_RAW_TRANSACTIONS_CONTAINER_PRODUCTION");
        String stagingContainer = requiredEnv("CENTINELA_RAW_TRANSACTIONS_CONTAINER_STAGING");
        String productionQueue = requiredEnv("CENTINELA_FLAGGED_CASES_QUEUE_PRODUCTION");
        String stagingQueue = requiredEnv("CENTINELA_FLAGGED_CASES_QUEUE_STAGING");

        BlobServiceClient blobServiceClient = new BlobServiceClientBuilder()
                .endpoint("https://" + storageAccount + ".blob.core.windows.net")
                .credential(credential)
                .buildClient();

        KeyVaultConnectionStrings secrets = new KeyVaultConnectionStrings();
        MongoClient mongoClient = MongoClients.create(secrets.cosmosMongoConnectionString());
        MongoCollection<Document> collection = mongoClient
                .getDatabase(requiredEnv("COSMOS_DATABASE"))
                .getCollection(requiredEnv("COSMOS_COLLECTION"));

        RawTransactionReaderPort reader = new BlobRawTransactionReaderAdapter(
                blobServiceClient, OBJECT_MAPPER, Set.of(productionContainer, stagingContainer));
        TransactionHistoryPort history = new CosmosMongoTransactionHistoryAdapter(collection);
        CosmosMongoScorePersistenceAdapter persistence = new CosmosMongoScorePersistenceAdapter(collection);
        ScoringThresholdProvider threshold = new ScoringThresholdProvider();

        Map<String, ScoreTransactionService> servicesByContainer = Map.of(
                productionContainer, scoreService(storageAccount, productionQueue, credential, threshold, persistence),
                stagingContainer, scoreService(storageAccount, stagingQueue, credential, threshold, persistence));

        return new RuntimeDependencies(mongoClient, reader, history, servicesByContainer);
    }

    private static ScoreTransactionService scoreService(
            String storageAccount,
            String queueName,
            DefaultAzureCredential credential,
            ScoringThresholdProvider threshold,
            CosmosMongoScorePersistenceAdapter persistence) {
        QueueClient queueClient = new QueueClientBuilder()
                .endpoint("https://" + storageAccount + ".queue.core.windows.net")
                .queueName(queueName)
                .credential(credential)
                .buildClient();
        return new ScoreTransactionService(
                ScoreTransactionService.defaultRules(threshold),
                threshold,
                persistence,
                new StorageQueueFlaggedCasePublisher(queueClient, OBJECT_MAPPER),
                Clock.systemUTC());
    }

    private static String requiredEnv(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Missing required App Setting: " + name);
        }
        return value;
    }

    private record RuntimeDependencies(
            MongoClient mongoClient,
            RawTransactionReaderPort rawTransactionReader,
            TransactionHistoryPort historyPort,
            Map<String, ScoreTransactionService> servicesByContainer) {

        ScoreTransactionService scoreServiceFor(TransactionEventNotification notification) {
            String container = BlobRawTransactionReaderAdapter.containerFrom(notification.blobPath());
            ScoreTransactionService service = servicesByContainer.get(container);
            if (service == null) {
                throw new IllegalArgumentException("No scoring route configured for Blob container " + container);
            }
            return service;
        }
    }
}
