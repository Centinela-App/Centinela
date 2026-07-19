package com.centinela.identityaccess;

import org.junit.jupiter.api.Test;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.oauth2.jwt.Jwt;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Unidad: verifica que {@link EntraRolesJwtAuthenticationConverter} traduce
 * cada app role de Entra al authority ROLE_* correspondiente y no otorga
 * authorities para claims desconocidos o ausentes.
 *
 * <p>No levanta contexto Spring; es la prueba rapida referenciada en el
 * comando de validacion {@code mvn -Dtest=EndpointAuthorizationTest test}.
 */
class EndpointAuthorizationTest {

    private final EntraRolesJwtAuthenticationConverter converter = new EntraRolesJwtAuthenticationConverter();

    @Test
    void should_map_service_role_to_role_service() {
        assertThat(authoritiesFor("SERVICE")).containsExactly("ROLE_SERVICE");
    }

    @Test
    void should_map_analyst_role_to_role_analyst() {
        assertThat(authoritiesFor("ANALYST")).containsExactly("ROLE_ANALYST");
    }

    @Test
    void should_map_administrator_role_to_role_administrator() {
        assertThat(authoritiesFor("ADMINISTRATOR")).containsExactly("ROLE_ADMINISTRATOR");
    }

    @Test
    void should_map_auditor_role_to_role_auditor() {
        assertThat(authoritiesFor("AUDITOR")).containsExactly("ROLE_AUDITOR");
    }

    @Test
    void should_map_multiple_roles_present_in_the_same_token() {
        assertThat(authoritiesFor("SERVICE", "AUDITOR"))
                .containsExactlyInAnyOrder("ROLE_SERVICE", "ROLE_AUDITOR");
    }

    @Test
    void should_ignore_unrecognized_role_values() {
        assertThat(authoritiesFor("SERVICE", "UNKNOWN_AZURE_RBAC_ROLE"))
                .containsExactly("ROLE_SERVICE");
    }

    @Test
    void should_grant_no_authorities_when_roles_claim_is_absent() {
        Jwt jwt = jwtWithClaims(Map.of());

        AbstractAuthenticationToken authentication = converter.convert(jwt);

        assertThat(authentication.getAuthorities()).isEmpty();
    }

    private Set<String> authoritiesFor(String... roles) {
        Jwt jwt = jwtWithClaims(Map.of("roles", List.of(roles)));

        AbstractAuthenticationToken authentication = converter.convert(jwt);

        return authentication.getAuthorities().stream()
                .map(Object::toString)
                .collect(Collectors.toSet());
    }

    private static Jwt jwtWithClaims(Map<String, Object> extraClaims) {
        Jwt.Builder builder = Jwt.withTokenValue("synthetic-token")
                .header("alg", "none")
                .issuedAt(Instant.EPOCH)
                .expiresAt(Instant.EPOCH.plusSeconds(3600))
                .claim("sub", "synthetic-subject");
        extraClaims.forEach(builder::claim);
        return builder.build();
    }
}
