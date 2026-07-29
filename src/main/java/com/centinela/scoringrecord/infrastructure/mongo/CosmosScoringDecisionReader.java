package com.centinela.scoringrecord.infrastructure.mongo;

import com.centinela.scoringrecord.application.port.out.ScoringDecisionReaderPort;
import com.centinela.scoringrecord.domain.model.RuleActivation;
import com.centinela.scoringrecord.domain.model.ScoringDecision;
import com.mongodb.client.MongoCollection;
import org.bson.Document;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

import static com.mongodb.client.model.Filters.eq;

/**
 * Lee de Cosmos el registro que dejo el motor al puntuar la transaccion.
 *
 * <p>Es una lectura <b>estrictamente de solo lectura</b>: el explicador nunca corrige ni
 * completa lo que el motor escribio. Si el registro es insuficiente, la correccion
 * corresponde al motor, y forzarla aqui ocultaria el defecto.
 *
 * <p>La consulta no filtra por {@code accountId}, que es la clave de particion, porque el
 * explicador solo conoce el {@code transactionId} del caso. Es una consulta entre
 * particiones: aceptable por su volumen — una por caso marcado, no una por transaccion —
 * y acotada por el indice unico de {@code transactionId}.
 */
public final class CosmosScoringDecisionReader implements ScoringDecisionReaderPort {

    private final MongoCollection<Document> collection;

    public CosmosScoringDecisionReader(MongoCollection<Document> collection) {
        this.collection = Objects.requireNonNull(collection, "collection is required");
    }

    @Override
    public Optional<ScoringDecision> findByTransactionId(String transactionId) {
        Document document = collection.find(eq("transactionId", transactionId)).first();
        if (document == null) {
            return Optional.empty();
        }

        Document score = document.get("score", Document.class);
        if (score == null) {
            return Optional.empty();
        }

        return Optional.of(new ScoringDecision(
                document.getString("transactionId"),
                document.getString("accountId"),
                intValue(score.get("total")),
                intValue(score.get("threshold")),
                document.getString("traceparent"),
                ruleActivations(score)));
    }

    @SuppressWarnings("unchecked")
    private static List<RuleActivation> ruleActivations(Document score) {
        Object rules = score.get("triggeredRules");
        if (!(rules instanceof List<?> ruleList)) {
            return List.of();
        }

        List<RuleActivation> activations = new ArrayList<>();
        for (Object element : ruleList) {
            if (!(element instanceof Document rule)) {
                continue;
            }
            Document observed = rule.get("observedValues", Document.class);
            Map<String, Object> observedValues = new LinkedHashMap<>();
            if (observed != null) {
                // Se descartan claves sin valor: un null convertido en cero o en cadena
                // vacia se volveria una afirmacion falsa dentro de la explicacion.
                observed.forEach((key, value) -> {
                    if (value != null) {
                        observedValues.put(key, value);
                    }
                });
            }
            activations.add(new RuleActivation(
                    rule.getString("ruleId"),
                    rule.getString("ruleName"),
                    intValue(rule.get("points")),
                    observedValues));
        }
        return activations;
    }

    private static int intValue(Object value) {
        return value instanceof Number number ? number.intValue() : 0;
    }
}
