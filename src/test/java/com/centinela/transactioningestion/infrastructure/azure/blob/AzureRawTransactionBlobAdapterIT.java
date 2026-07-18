package com.centinela.transactioningestion.infrastructure.azure.blob;

import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.centinela.transactioningestion.domain.model.Location;
import com.centinela.transactioningestion.domain.model.Merchant;
import com.centinela.transactioningestion.domain.model.Transaction;
import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import java.math.BigDecimal;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AzureRawTransactionBlobAdapterIT {

    @Test
    void should_build_blob_path_with_utc_reception_date() {
        String path = new BlobPathFactory().create(
                Instant.parse("2026-07-19T00:30:00Z"),
                "tx-path-1001");

        assertEquals("2026/07/19/tx-path-1001.json", path);
    }

    @Test
    @EnabledIfEnvironmentVariable(named = "CENTINELA_RUN_AZURE_IT", matches = "(?i)true")
    void should_store_raw_transaction_in_environment_container() throws Exception {
        String accountName = requiredEnvironment("CENTINELA_STORAGE_ACCOUNT");
        String containerName = requiredEnvironment("CENTINELA_RAW_TRANSACTIONS_CONTAINER");
        BlobContainerClient containerClient = new BlobServiceClientBuilder()
                .endpoint("https://" + accountName + ".blob.core.windows.net")
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient()
                .getBlobContainerClient(containerName);

        ObjectMapper mapper = new ObjectMapper()
                .registerModule(new JavaTimeModule())
                .enable(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)
                .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
                .setSerializationInclusion(JsonInclude.Include.NON_NULL);
        BlobPathFactory pathFactory = new BlobPathFactory();
        AzureRawTransactionBlobAdapter adapter = new AzureRawTransactionBlobAdapter(
                containerClient,
                mapper,
                pathFactory);

        String transactionId = "it-" + UUID.randomUUID();
        Instant receivedAt = Instant.now();
        String expectedPath = pathFactory.create(receivedAt, transactionId);
        Transaction transaction = transaction(transactionId);

        try {
            adapter.store(transaction, receivedAt);

            var blobClient = containerClient.getBlobClient(expectedPath);
            assertTrue(blobClient.exists(), "The transaction blob must exist after store returns");
            JsonNode stored = mapper.readTree(blobClient.downloadContent().toString());
            assertEquals(mapper.valueToTree(transaction), stored);
            assertEquals(transactionId, stored.path("transactionId").asText());
            assertFalse(stored.path("location").has("latitude"));
            assertFalse(stored.path("location").has("longitude"));
            assertFalse(stored.has("score"));
            assertFalse(stored.has("decision"));
            assertFalse(stored.has("rules"));
            assertFalse(stored.has("caseId"));
        } finally {
            containerClient.getBlobClient(expectedPath).deleteIfExists();
        }
    }

    private static Transaction transaction(String transactionId) {
        return new Transaction(
                transactionId,
                "acct-it-2001",
                new BigDecimal("125000.25"),
                "COP",
                OffsetDateTime.parse("2026-07-18T10:00:00-05:00"),
                new Location("CO", "Bogota", null, null),
                new Merchant("Comercio Integracion", "RETAIL"));
    }

    private static String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(name + " is required when CENTINELA_RUN_AZURE_IT=true");
        }
        return value;
    }
}
