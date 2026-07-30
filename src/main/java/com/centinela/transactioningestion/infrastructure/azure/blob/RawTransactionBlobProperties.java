package com.centinela.transactioningestion.infrastructure.azure.blob;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Configuracion no secreta del Blob de transacciones crudas.
 *
 * <p>{@code connectionString} existe unicamente para el entorno local con Azurite. En
 * Azure permanece vacia y la autenticacion es por Managed Identity — una cadena de
 * conexion real de Azure aqui seria una credencial en configuracion, que es justo lo que
 * el proyecto prohibe. La de Azurite no lo es: su clave es una constante publica
 * documentada por Microsoft, identica en toda instalacion del emulador.
 */
@ConfigurationProperties(prefix = "centinela.storage.blob")
public record RawTransactionBlobProperties(
        String accountName,
        String containerName,
        String connectionString) {

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

    /** {@code true} cuando el destino es un emulador local y no Azure. */
    public boolean usesConnectionString() {
        return connectionString != null && !connectionString.isBlank();
    }
}
