package com.centinela.documentstorage.contract;

import com.centinela.documentstorage.infrastructure.web.dto.DocumentReceiptResponse;
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

class VerificationDocumentOpenApiContractTest {

    private static final Path OPEN_API = Path.of(
            "docs", "1_Requisitos_y_Contrato", "openapi-centinela-semana1.yaml");

    @Test
    void documentEndpointConsumesMultipartAndDocumentsExpectedResponses() throws IOException {
        Map<String, Object> document = loadOpenApi();
        Map<String, Object> paths = map(document.get("paths"));
        Map<String, Object> endpoint = map(paths.get("/api/v1/verification-documents"));
        Map<String, Object> post = map(endpoint.get("post"));
        Map<String, Object> requestBody = map(post.get("requestBody"));
        Map<String, Object> content = map(requestBody.get("content"));
        Map<String, Object> multipart = map(content.get("multipart/form-data"));
        Map<String, Object> requestSchema = map(multipart.get("schema"));
        Map<String, Object> responses = map(post.get("responses"));

        assertThat(content.keySet()).containsExactly("multipart/form-data");
        assertThat(requestSchema.get("additionalProperties")).isEqualTo(false);
        assertThat(responses.keySet()).contains("201", "400", "503");
    }

    @Test
    void documentReceiptIsClosedMatchesJavaAndHasNoCaseAssociation() throws IOException {
        Map<String, Object> schemas = map(map(loadOpenApi().get("components")).get("schemas"));
        Map<String, Object> receipt = map(schemas.get("DocumentReceipt"));
        Set<String> schemaProperties = map(receipt.get("properties")).keySet();
        Set<String> recordComponents = Arrays.stream(DocumentReceiptResponse.class.getRecordComponents())
                .map(component -> component.getName())
                .collect(Collectors.toSet());

        assertThat(receipt.get("additionalProperties")).isEqualTo(false);
        assertThat(schemaProperties).containsExactlyInAnyOrderElementsOf(recordComponents);
        assertThat(schemaProperties).doesNotContain("caseId");
        assertThat(map(map(receipt.get("properties")).get("status")).get("enum"))
                .isEqualTo(java.util.List.of("STORED"));
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
}
