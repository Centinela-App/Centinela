package com.centinela.identityaccess;

import com.centinela.transactioningestion.application.port.out.RawTransactionStoragePort;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Instant;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * TEST-S1-021: solo el rol SERVICE puede autorizar transacciones.
 *
 * <p>Los filtros de seguridad se dejan activos (a diferencia de
 * {@code TransactionApiIT}, que los desactiva para probar el caso de uso de
 * forma aislada). {@link JwtDecoder} se mockea para no depender de un token
 * real de Entra ni de acceso de red.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class TransactionEndpointAuthorizationIT {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private JwtDecoder jwtDecoder;

    @MockBean
    private RawTransactionStoragePort storagePort;

    @Test
    void should_return_401_without_a_bearer_token() throws Exception {
        mockMvc.perform(post("/api/v1/transactions")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validPayload()))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"))
                .andExpect(jsonPath("$.message").exists());

        verify(storagePort, never()).store(any(), any());
    }

    @Test
    void should_authorize_service_role_to_ingest_transactions() throws Exception {
        given(jwtDecoder.decode(anyString())).willReturn(jwtWithRoles("SERVICE"));

        mockMvc.perform(post("/api/v1/transactions")
                        .header("Authorization", "Bearer synthetic-service-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validPayload()))
                .andExpect(status().isAccepted());

        verify(storagePort).store(any(), any());
    }

    @ParameterizedTest
    @ValueSource(strings = {"ANALYST", "ADMINISTRATOR", "AUDITOR"})
    void should_return_403_for_roles_other_than_service(String role) throws Exception {
        given(jwtDecoder.decode(anyString())).willReturn(jwtWithRoles(role));

        mockMvc.perform(post("/api/v1/transactions")
                        .header("Authorization", "Bearer synthetic-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(validPayload()))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("FORBIDDEN"))
                .andExpect(jsonPath("$.message").exists());

        verify(storagePort, never()).store(any(), any());
    }

    private static Jwt jwtWithRoles(String... roles) {
        return Jwt.withTokenValue("synthetic-token")
                .header("alg", "none")
                .issuedAt(Instant.now())
                .expiresAt(Instant.now().plusSeconds(3600))
                .claim("sub", "synthetic-subject")
                .claim("roles", List.of(roles))
                .build();
    }

    private static String validPayload() {
        return """
                {
                  "transactionId": "tx-auth-1001",
                  "accountId": "acct-auth-2001",
                  "amount": 50000.00,
                  "currency": "COP",
                  "occurredAt": "2026-07-18T10:00:00-05:00",
                  "location": {
                    "countryCode": "CO",
                    "city": "Bogota"
                  },
                  "merchant": {
                    "name": "Comercio Demo",
                    "category": "RETAIL"
                  }
                }
                """;
    }
}
