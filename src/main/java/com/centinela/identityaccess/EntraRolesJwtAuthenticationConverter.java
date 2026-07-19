package com.centinela.identityaccess;

import org.springframework.core.convert.converter.Converter;
import org.springframework.security.authentication.AbstractAuthenticationToken;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;

import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Traduce los app roles funcionales de Entra ID (claim {@code roles}) a
 * authorities Spring Security con prefijo {@code ROLE_}.
 *
 * <p>Los app roles de Entra son un concepto de negocio, no deben confundirse
 * con Azure RBAC. Solo se reconocen los cuatro roles previstos para Semana 1;
 * cualquier otro valor presente en el claim se ignora para evitar que un
 * claim inesperado otorgue una autoridad no prevista.
 */
public class EntraRolesJwtAuthenticationConverter implements Converter<Jwt, AbstractAuthenticationToken> {

    private static final String ROLES_CLAIM = "roles";

    private static final Set<String> RECOGNIZED_ROLES =
            Set.of("SERVICE", "ANALYST", "ADMINISTRATOR", "AUDITOR");

    @Override
    public AbstractAuthenticationToken convert(Jwt jwt) {
        Collection<GrantedAuthority> authorities = extractRoles(jwt).stream()
                .filter(RECOGNIZED_ROLES::contains)
                .map(role -> new SimpleGrantedAuthority("ROLE_" + role))
                .collect(Collectors.toUnmodifiableSet());

        return new JwtAuthenticationToken(jwt, authorities);
    }

    private static List<String> extractRoles(Jwt jwt) {
        List<String> roles = jwt.getClaimAsStringList(ROLES_CLAIM);
        return roles == null ? List.of() : roles;
    }
}
