package com.centinela.scoring.infrastructure.config;

import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;

/**
 * Resuelve secretos (cadenas de conexion) desde Key Vault usando la Managed
 * Identity de la Function ({@link DefaultAzureCredentialBuilder}). Ningun
 * secreto vive en codigo ni en App Settings en claro: solo el nombre del
 * Key Vault ({@code KEY_VAULT_URI}) es configuracion publica.
 */
public final class KeyVaultConnectionStrings {

    static final String KEY_VAULT_URI_SETTING = "KEY_VAULT_URI";
    static final String COSMOS_CONNECTION_SECRET = "cosmos-connection-string";
    static final String QUEUE_CONNECTION_SECRET = "case-queue-connection-string";

    private final SecretClient secretClient;

    public KeyVaultConnectionStrings() {
        String keyVaultUri = requiredEnv(KEY_VAULT_URI_SETTING);
        this.secretClient = new SecretClientBuilder()
                .vaultUrl(keyVaultUri)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
    }

    public String cosmosConnectionString() {
        return secretClient.getSecret(COSMOS_CONNECTION_SECRET).getValue();
    }

    public String caseQueueConnectionString() {
        return secretClient.getSecret(QUEUE_CONNECTION_SECRET).getValue();
    }

    private static String requiredEnv(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Missing required App Setting: " + name);
        }
        return value;
    }
}
