package com.centinela.scoring.infrastructure.function;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.microsoft.azure.functions.*;
import com.microsoft.azure.functions.annotation.FunctionName;
import com.microsoft.azure.functions.annotation.EventHubTrigger;

import com.centinela.scoring.application.service.ScoreTransactionService;
import com.centinela.scoring.domain.model.Score;
import com.centinela.scoring.infrastructure.config.ScoringConfiguration;

import java.util.Map;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * Azure Function que procesa eventos de transaccion para scoring.
 *
 * <p>Trigger: Azure Event Hub (topic: transaction-event-v1)
 *
 * <p>Flujo:
 * 1. Recibir evento de transaccion
 * 2. Extraer transactionId y accountId
 * 3. Ejecutar scoring (calcular, persistir, publicar caso si aplica)
 * 4. Registrar resultado
 */
public final class ScoreTransactionFunction {

    private static final String FUNCTION_NAME = "ScoreTransactionFunction";

    private final ScoreTransactionServiceWrapper serviceWrapper;

    public ScoreTransactionFunction() {
        this.serviceWrapper = new ScoreTransactionServiceWrapper();
    }

    /**
     * Punto de entrada triggered por Event Hub.
     *
     * @param message el mensaje de transaccion
     * @param context contexto de la function
     * @return resultado de la ejecucion
     */
    @FunctionName(FUNCTION_NAME)
    public HttpResponseMessage run(
            @EventHubTrigger(
                    name = "transactionMessage",
                    eventHubName = "",
                    connection = "EVENT_HUB_CONNECTION_STRING"
            ) String message,
            final ExecutionContext context) {

        Logger logger = context.getLogger();
        
        try {
            logger.log(Level.INFO, FUNCTION_NAME + ": Processing transaction message");
            context.getLogger().log(Level.INFO, "Event payload: " + message);

            // Parsear evento
            TransactionEvent transactionEvent = parseEvent(message, logger);

            // Ejecutar scoring
            Score score = serviceWrapper.executeScoring(
                    transactionEvent.transactionId(),
                    transactionEvent.accountId(),
                    logger
            );

            logger.log(Level.INFO, String.format(
                    "%s: Scored transaction %s with total score %d",
                    FUNCTION_NAME,
                    score.transactionId(),
                    score.totalScore()
            ));

            // Loguear si se publico caso
            if (score.totalScore() >= ScoringConfiguration.createScoringThreshold()) {
                logger.log(Level.INFO, String.format(
                        "%s: Flagged case published for transaction %s (score %d >= threshold %d)",
                        FUNCTION_NAME,
                        score.transactionId(),
                        score.totalScore(),
                        ScoringConfiguration.createScoringThreshold()
                ));
            }

            return new HttpResponseMessageStub(
                    new SimpleHttpStatusType(200, "OK"),
                    "{\"status\":\"success\",\"transactionId\":\"" + score.transactionId() + "\",\"score\":" + score.totalScore() + "}"
            );

        } catch (Exception e) {
            logger.log(Level.SEVERE, FUNCTION_NAME + ": Error processing transaction event: " + e.getMessage(), e);
            return new HttpResponseMessageStub(
                    new SimpleHttpStatusType(500, "Internal Server Error"),
                    "{\"error\":\"Error processing transaction: " + e.getMessage() + "\"}"
            );
        }
    }

    private TransactionEvent parseEvent(String message, Logger logger) throws Exception {
        ObjectMapper mapper = ScoringConfiguration.createObjectMapper();
        @SuppressWarnings("unchecked")
        Map<String, Object> eventData = mapper.readValue(message, Map.class);

        String transactionId = (String) eventData.get("transactionId");
        String accountId = (String) eventData.get("accountId");

        if (transactionId == null || transactionId.isBlank()) {
            throw new IllegalArgumentException("transactionId is required in event");
        }
        if (accountId == null || accountId.isBlank()) {
            throw new IllegalArgumentException("accountId is required in event");
        }

        return new TransactionEvent(transactionId, accountId);
    }

    /**
     * Representacion del evento de transaccion.
     */
    private record TransactionEvent(String transactionId, String accountId) {}

    /**
     * Implementacion simple de HttpStatusType.
     */
    private static class SimpleHttpStatusType implements HttpStatusType {
        private final int statusCode;
        private final String reason;

        SimpleHttpStatusType(int statusCode, String reason) {
            this.statusCode = statusCode;
            this.reason = reason;
        }

        public int value() {
            return statusCode;
        }

        public String getReasonPhrase() {
            return reason;
        }

        public String reasonPhrase() {
            return reason;
        }
    }

    /**
     * Stub simple de HttpResponseMessage para evitar problemas de compatibilidad.
     */
    private static class HttpResponseMessageStub implements HttpResponseMessage {
        private final HttpStatusType status;
        private final String body;

        HttpResponseMessageStub(HttpStatusType status, String body) {
            this.status = status;
            this.body = body;
        }

        @Override
        public HttpStatusType getStatus() {
            return status;
        }

        @Override
        public String getBody() {
            return body;
        }

        @Override
        public String getHeader(String name) {
            if ("Content-Type".equals(name)) {
                return "application/json";
            }
            return null;
        }
    }

    /**
     * Wrapper para inicializar el servicio de scoring lazily.
     */
    private static class ScoreTransactionServiceWrapper {
        private volatile ScoreTransactionService service;
        private volatile ObjectMapper objectMapper;
        
        ScoreTransactionServiceWrapper() {
            // Inicializacion lazy para evitar problemas con Azure Functions
        }
        
        private ScoreTransactionService getService() {
            if (service == null) {
                synchronized (this) {
                    if (service == null) {
                        objectMapper = ScoringConfiguration.createObjectMapper();
                        
                        var cosmosClient = ScoringConfiguration.createCosmosClient();
                        var cosmosContainer = ScoringConfiguration.createCosmosContainer(cosmosClient);
                        var queueClient = ScoringConfiguration.createFlaggedCasesQueueClient();
                        
                        var persistencePort = ScoringConfiguration.createScorePersistencePort(cosmosContainer, objectMapper);
                        var publisherPort = ScoringConfiguration.createFlaggedCasePublisherPort(queueClient, objectMapper);
                        
                        service = ScoringConfiguration.createScoreTransactionService(
                                objectMapper,
                                persistencePort,
                                publisherPort
                        );
                    }
                }
            }
            return service;
        }
        
        Score executeScoring(String transactionId, String accountId, Logger logger) {
            try {
                return getService().executeScoring(transactionId, accountId);
            } catch (Exception e) {
                logger.log(Level.SEVERE, "Error in scoring: " + e.getMessage(), e);
                throw new RuntimeException("Scoring failed", e);
            }
        }
    }
}
