package com.centinela.documentstorage.infrastructure.azure.blob;

import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.storage.blob.BlobContainerClient;
import com.azure.storage.blob.BlobServiceClientBuilder;
import com.centinela.documentstorage.domain.model.VerificationDocument;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertArrayEquals;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AzureVerificationDocumentBlobAdapterIT {

    @Test
    void should_build_safe_document_path_with_utc_reception_date() {
        VerificationDocument document = new VerificationDocument(
                "doc-path-1001",
                "technical_evidence.txt",
                new byte[]{1});

        String path = AzureVerificationDocumentBlobAdapter.createBlobPath(
                Instant.parse("2026-07-19T00:30:00Z"),
                document);

        assertEquals(
                "2026/07/19/doc-path-1001/technical_evidence.txt",
                path);
    }

    @Test
    @EnabledIfEnvironmentVariable(
            named = "CENTINELA_RUN_AZURE_DOCUMENT_IT",
            matches = "(?i)true")
    void should_store_document_in_environment_container() {
        String accountName = requiredEnvironment("CENTINELA_STORAGE_ACCOUNT");
        String containerName = requiredEnvironment("CENTINELA_VERIFICATION_DOCUMENTS_CONTAINER");
        BlobContainerClient containerClient = new BlobServiceClientBuilder()
                .endpoint("https://" + accountName + ".blob.core.windows.net")
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient()
                .getBlobContainerClient(containerName);

        AzureVerificationDocumentBlobAdapter adapter =
                new AzureVerificationDocumentBlobAdapter(containerClient);
        String documentId = "doc-it-" + UUID.randomUUID();
        byte[] expectedContent = "synthetic verification document"
                .getBytes(StandardCharsets.UTF_8);
        VerificationDocument document = new VerificationDocument(
                documentId,
                "verification.txt",
                expectedContent);
        Instant receivedAt = Instant.now();
        String expectedPath = AzureVerificationDocumentBlobAdapter.createBlobPath(
                receivedAt,
                document);

        try {
            adapter.store(document, receivedAt);

            var blobClient = containerClient.getBlobClient(expectedPath);
            assertTrue(blobClient.exists(), "The document blob must exist after store returns");
            assertArrayEquals(expectedContent, blobClient.downloadContent().toBytes());
            assertEquals(expectedContent.length, blobClient.getProperties().getBlobSize());
        } finally {
            containerClient.getBlobClient(expectedPath).deleteIfExists();
        }
    }

    private static String requiredEnvironment(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException(
                    name + " is required when CENTINELA_RUN_AZURE_DOCUMENT_IT=true");
        }
        return value;
    }
}
