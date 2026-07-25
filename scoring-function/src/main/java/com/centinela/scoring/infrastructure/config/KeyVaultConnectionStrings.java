package com.centinela.scoring.infrastructure.config;

import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;

/** Resuelve la cadena Mongo de Cosmos desde Key Vault mediante Managed Identity. */
public final class KeyVaultConnectionStrings {
    static final String KEY_VAULT_URI_SETTING = "KEY_VAULT_URI";
    static final String COSMOS_MONGO_CONNECTION_SECRET = "cosmos-mongo-connection-string";

    private final SecretClient secretClient;

    public KeyVaultConnectionStrings() {
        this(new SecretClientBuilder()
                .vaultUrl(requiredEnv(KEY_VAULT_URI_SETTING))
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient());
    }

    KeyVaultConnectionStrings(SecretClient secretClient) {
        this.secretClient = secretClient;
    }

    public String cosmosMongoConnectionString() {
        return secretClient.getSecret(COSMOS_MONGO_CONNECTION_SECRET).getValue();
    }

    private static String requiredEnv(String name) {
        String value = System.getenv(name);
        if (value == null || value.isBlank()) {
            throw new IllegalStateException("Missing required App Setting: " + name);
        }
        return value;
    }
}
