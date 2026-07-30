package com.centinela.transactioningestion.contract;

import com.centinela.shared.web.ErrorResponse;
import com.centinela.transactioningestion.infrastructure.web.dto.LocationRequest;
import com.centinela.transactioningestion.infrastructure.web.dto.MerchantRequest;
import com.centinela.transactioningestion.infrastructure.web.dto.TransactionReceiptResponse;
import com.centinela.transactioningestion.infrastructure.web.dto.TransactionRequest;
import org.junit.jupiter.api.Test;
import org.yaml.snakeyaml.Yaml;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

class OpenApiContractTest {

    private static final Path OPEN_API = Path.of(
            "docs", "contracts", "openapi-centinela.yaml");

    @Test
    void transactionEndpointConsumesOnlyJsonAndDocumentsExpectedResponses() throws IOException {
        Map<String, Object> document = loadOpenApi();
        Map<String, Object> post = map(map(document.get("paths")).get("/api/v1/transactions"), "post");
        Map<String, Object> content = map(map(post.get("requestBody")).get("content"));
        Map<String, Object> responses = map(post.get("responses"));

        assertThat(content.keySet()).containsExactly("application/json");
        assertThat(responses.keySet()).contains("202", "400");
    }

    @Test
    void openApiAndJavaExposeExactlyTheApprovedRequestFields() throws IOException {
        Map<String, Object> schemas = schemas();

        assertSchemaMatchesRecord(map(schemas.get("TransactionRequest")), TransactionRequest.class);
        assertSchemaMatchesRecord(map(schemas.get("Location")), LocationRequest.class);
        assertSchemaMatchesRecord(map(schemas.get("Merchant")), MerchantRequest.class);
    }

    @Test
    void receiptAndErrorResponsesAreClosedAndMatchJava() throws IOException {
        Map<String, Object> schemas = schemas();

        Map<String, Object> receipt = map(schemas.get("TransactionReceipt"));
        assertSchemaMatchesRecord(receipt, TransactionReceiptResponse.class);
        assertThat(map(map(receipt.get("properties")).get("status")).get("enum"))
                .isEqualTo(java.util.List.of("RECEIVED"));

        assertSchemaMatchesRecord(map(schemas.get("ErrorResponse")), ErrorResponse.class);
    }

    @Test
    void transactionSchemasDoNotContainWeekTwoFields() throws IOException {
        Map<String, Object> schemas = schemas();
        Set<String> futureFields = Set.of("score", "decision", "rules", "triggeredRules", "caseId");

        for (String schemaName : Set.of("TransactionRequest", "Location", "Merchant", "TransactionReceipt")) {
            Set<String> propertyNames = map(map(schemas.get(schemaName)).get("properties")).keySet();
            assertThat(propertyNames).doesNotContainAnyElementsOf(futureFields);
        }
    }

    private static void assertSchemaMatchesRecord(Map<String, Object> schema, Class<?> recordType) {
        Set<String> schemaProperties = map(schema.get("properties")).keySet();
        Set<String> recordComponents = Arrays.stream(recordType.getRecordComponents())
                .map(component -> component.getName())
                .collect(Collectors.toSet());

        assertThat(schema.get("additionalProperties")).isEqualTo(false);
        assertThat(schemaProperties).containsExactlyInAnyOrderElementsOf(recordComponents);
    }

    private static Map<String, Object> schemas() throws IOException {
        Map<String, Object> document = loadOpenApi();
        return map(map(document.get("components")).get("schemas"));
    }

    private static Map<String, Object> loadOpenApi() throws IOException {
        try (InputStream input = Files.newInputStream(OPEN_API)) {
            return map(new Yaml().load(input));
        }
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> map(Object value) {
        return (Map<String, Object>) value;
    }

    private static Map<String, Object> map(Object value, String key) {
        return map(map(value).get(key));
    }
}
