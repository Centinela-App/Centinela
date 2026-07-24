package com.centinela.scoring.infrastructure.cosmos;

import com.azure.cosmos.CosmosContainer;
import com.azure.cosmos.models.CosmosItemRequestOptions;
import com.azure.cosmos.models.CosmosItemResponse;
import com.azure.cosmos.models.PartitionKey;
import com.centinela.scoring.application.exception.ScorePersistenceException;
import com.centinela.scoring.application.port.out.ScorePersistencePort;
import com.centinela.scoring.domain.model.RuleHit;
import com.centinela.scoring.domain.model.Score;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Adaptador Cosmos DB para persistir el score junto a la transaccion.
 *
 * <p>Persiste en la misma coleccion y particion (accountId) que la transaccion
 * para optimizar consultas por cuenta. La idempotencia se garantiza usando
 * el documentType como discriminador y transactionId como parte de la clave.
 */
public final class CosmosScorePersistenceAdapter implements ScorePersistencePort {

    private static final String DOCUMENT_TYPE_SCORE = "SCORE";

    private final CosmosContainer container;
    private final ObjectMapper objectMapper;

    public CosmosScorePersistenceAdapter(CosmosContainer container, ObjectMapper objectMapper) {
        this.container = container;
        this.objectMapper = objectMapper.copy()
                .setSerializationInclusion(JsonInclude.Include.NON_NULL);
    }

    @Override
    public void persistScore(Score score) {
        try {
            Map<String, Object> document = buildDocument(score);

            // Upsert para garantizar idempotencia: re-procesar el mismo evento
            // no duplica el score, lo actualiza con el mismo contenido.
            CosmosItemRequestOptions options = new CosmosItemRequestOptions();
            // La idempotencia se logra porque el ID es deterministico basado en transactionId
            CosmosItemResponse<Object> response = container.upsertItem(
                    document,
                    new PartitionKey(score.accountId()),
                    options
            );

        } catch (RuntimeException e) {
            throw new ScorePersistenceException("Failed to persist score for transaction: " + score.transactionId(), e);
        }
    }

    /**
     * Construye el documento de score para persistir en Cosmos.
     * Incluye el score y el detalle de activacion (triggeredRules con valores observados).
     */
    private Map<String, Object> buildDocument(Score score) {
        Map<String, Object> document = new HashMap<>();

        // Clave compuesta para garantizar unicidad por transactionId
        document.put("id", "SCORE#" + score.transactionId());
        document.put("transactionId", score.transactionId());
        document.put("accountId", score.accountId());
        document.put("documentType", DOCUMENT_TYPE_SCORE);

        // Score y detalle
        document.put("totalScore", score.totalScore());
        document.put("scoredAt", score.scoredAt().toString());

        // Detalle de activacion con valores observados
        List<Map<String, Object>> triggeredRulesData = score.triggeredRules().stream()
                .map(this::ruleHitToMap)
                .toList();
        document.put("triggeredRules", triggeredRulesData);

        return document;
    }

    private Map<String, Object> ruleHitToMap(RuleHit ruleHit) {
        Map<String, Object> map = new HashMap<>();
        map.put("ruleId", ruleHit.ruleId());
        map.put("ruleName", ruleHit.ruleName());
        map.put("points", ruleHit.points());
        map.put("observedValues", ruleHit.observedValues());
        return map;
    }
}
