package com.centinela.transactioningestion.infrastructure.azure.blob;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Configuracion no secreta del Blob de transacciones crudas.
 */
@ConfigurationProperties(prefix = "centinela.storage.blob")
public record RawTransactionBlobProperties(String accountName, String containerName) {

    public RawTransactionBlobProperties {
        if (accountName == null || accountName.isBlank()) {
            throw new IllegalArgumentException("centinela.storage.blob.account-name is required");
        }
        if (containerName == null || containerName.isBlank()) {
            throw new IllegalArgumentException("centinela.storage.blob.container-name is required");
        }
    }

    public String endpoint() {
        return "https://" + accountName + ".blob.core.windows.net";
    }
}
