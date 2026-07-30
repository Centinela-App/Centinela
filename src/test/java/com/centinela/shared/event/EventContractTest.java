package com.centinela.shared.event;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Set;
import java.util.stream.Collectors;
import java.util.stream.StreamSupport;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Prueba de contrato (TEST-S2-005): verifica que los esquemas JSON versionados y
 * los records Java compartidos describen exactamente la misma forma.
 *
 * <p>Cubre los dos contratos que cruzan el pipeline:
 * <ul>
 *   <li>{@code transaction-event-v1} (API -&gt; Event Grid -&gt; Function), sin score.</li>
 *   <li>{@code flagged-case-v1} (Function -&gt; cola -&gt; consumidor), con score y
 *       resumen de reglas activadas.</li>
 * </ul>
 *
 * <p>Al comparar el conjunto de propiedades del esquema con los componentes del
 * record, cualquier campo agregado en uno solo de los dos lados rompe la prueba, lo
 * que fuerza a mantenerlos sincronizados.
 */
class EventContractTest {

    private static final Path SCHEMAS =
            Path.of("docs", "contracts", "schemas");
    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Test
    void transactionEventSchemaMatchesRecord() throws IOException {
        JsonNode schema = loadSchema("transaction-event-v1.json");

        assertObjectIsClosed(schema);
        assertRequiredCoversAllProperties(schema);
        assertThat(propertyNames(schema))
                .containsExactlyInAnyOrderElementsOf(recordComponents(TransactionEvent.class));
    }

    @Test
    void transactionEventCarriesNoScoreNorDecision() throws IOException {
        Set<String> properties = propertyNames(loadSchema("transaction-event-v1.json"));

        assertThat(properties).doesNotContain("score", "decision", "triggeredRules", "caseId");
        assertThat(recordComponents(TransactionEvent.class))
                .doesNotContain("score", "decision");
    }

    @Test
    void flaggedCaseSchemaMatchesRecord() throws IOException {
        JsonNode schema = loadSchema("flagged-case-v1.json");

        assertObjectIsClosed(schema);
        assertRequiredCoversAllProperties(schema);
        assertThat(propertyNames(schema))
                .containsExactlyInAnyOrderElementsOf(recordComponents(FlaggedCaseMessage.class));
    }

    @Test
    void flaggedCaseCarriesScoreAndTriggeredRulesSummary() throws IOException {
        JsonNode schema = loadSchema("flagged-case-v1.json");
        JsonNode properties = schema.get("properties");

        assertThat(properties.has("score")).isTrue();
        assertThat(properties.get("score").get("type").asText()).isEqualTo("integer");

        JsonNode triggeredRules = properties.get("triggeredRules");
        assertThat(triggeredRules.get("type").asText()).isEqualTo("array");

        // El resumen de cada regla activada tambien debe coincidir con su record anidado.
        JsonNode item = triggeredRules.get("items");
        assertObjectIsClosed(item);
        assertRequiredCoversAllProperties(item);
        assertThat(propertyNames(item))
                .containsExactlyInAnyOrderElementsOf(
                        recordComponents(FlaggedCaseMessage.TriggeredRuleSummary.class));
    }

    @Test
    void bothSchemasDeclareTheirVersionConsistentlyWithRecords() throws IOException {
        assertThat(loadSchema("transaction-event-v1.json").get("title").asText())
                .isEqualTo(TransactionEvent.SCHEMA_VERSION);
        assertThat(loadSchema("flagged-case-v1.json").get("title").asText())
                .isEqualTo(FlaggedCaseMessage.SCHEMA_VERSION);
    }

    private static void assertObjectIsClosed(JsonNode objectSchema) {
        assertThat(objectSchema.get("type").asText()).isEqualTo("object");
        assertThat(objectSchema.get("additionalProperties").asBoolean()).isFalse();
    }

    private static void assertRequiredCoversAllProperties(JsonNode objectSchema) {
        Set<String> required = StreamSupport
                .stream(objectSchema.get("required").spliterator(), false)
                .map(JsonNode::asText)
                .collect(Collectors.toSet());
        assertThat(required).containsExactlyInAnyOrderElementsOf(propertyNames(objectSchema));
    }

    private static Set<String> propertyNames(JsonNode objectSchema) {
        Set<String> names = new java.util.HashSet<>();
        objectSchema.get("properties").fieldNames().forEachRemaining(names::add);
        return names;
    }

    private static Set<String> recordComponents(Class<?> recordType) {
        return Arrays.stream(recordType.getRecordComponents())
                .map(component -> component.getName())
                .collect(Collectors.toSet());
    }

    private static JsonNode loadSchema(String fileName) throws IOException {
        return MAPPER.readTree(Files.newBufferedReader(SCHEMAS.resolve(fileName)));
    }
}
