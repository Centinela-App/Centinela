package com.centinela.identityaccess;

import com.centinela.documentstorage.application.port.out.VerificationDocumentStoragePort;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * TEST-S1-022: solo el rol ANALYST puede cargar documentos de verificacion.
 *
 * <p>Los filtros de seguridad se dejan activos (a diferencia de
 * {@code VerificationDocumentApiIT}, que los desactiva para probar el caso
 * de uso de forma aislada). {@link JwtDecoder} se mockea para no depender de
 * un token real de Entra ni de acceso de red.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("test")
class DocumentEndpointAuthorizationIT {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private JwtDecoder jwtDecoder;

    @MockBean
    private VerificationDocumentStoragePort storagePort;

    @Test
    void should_return_401_without_a_bearer_token() throws Exception {
        mockMvc.perform(MockMvcRequestBuilders.multipart("/api/v1/verification-documents")
                        .file(sampleFile()))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHENTICATED"))
                .andExpect(jsonPath("$.message").exists());

        verify(storagePort, never()).store(any(), any());
    }

    @Test
    void should_authorize_analyst_role_to_store_documents() throws Exception {
        given(jwtDecoder.decode(anyString())).willReturn(jwtWithRoles("ANALYST"));

        mockMvc.perform(MockMvcRequestBuilders.multipart("/api/v1/verification-documents")
                        .file(sampleFile())
                        .header("Authorization", "Bearer synthetic-analyst-token"))
                .andExpect(status().isCreated());

        verify(storagePort).store(any(), any());
    }

    @ParameterizedTest
    @ValueSource(strings = {"SERVICE", "ADMINISTRATOR", "AUDITOR"})
    void should_return_403_for_roles_other_than_analyst(String role) throws Exception {
        given(jwtDecoder.decode(anyString())).willReturn(jwtWithRoles(role));

        mockMvc.perform(MockMvcRequestBuilders.multipart("/api/v1/verification-documents")
                        .file(sampleFile())
                        .header("Authorization", "Bearer synthetic-token"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("FORBIDDEN"))
                .andExpect(jsonPath("$.message").exists());

        verify(storagePort, never()).store(any(), any());
    }

    private static MockMultipartFile sampleFile() {
        return new MockMultipartFile(
                "file",
                "verification.txt",
                "text/plain",
                "synthetic-document".getBytes(StandardCharsets.UTF_8));
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
}
