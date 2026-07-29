package com.centinela.identityaccess;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidatorResult;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtValidators;
import org.springframework.security.oauth2.jwt.NimbusJwtDecoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.oauth2.jwt.Jwt;

import java.util.List;

/**
 * Configuracion HTTP de seguridad: Resource Server OAuth2/JWT sobre los
 * app roles de Entra.
 *
 * <p>El issuer, el audience y el JWK set URI se inyectan como variables de
 * entorno no secretas (ver {@code application.yml}); nunca se versionan
 * valores concretos de un tenant.
 */
// Fuera del perfil 'local': alli rige LocalSecurityConfiguration, que documenta por
// que y bajo que salvaguardas se apaga la autenticacion en el entorno de desarrollo.
@Configuration
@EnableWebSecurity
@Profile("!local")
public class SecurityConfiguration {

    private final String issuerUri;
    private final String audience;
    private final String jwkSetUri;

    public SecurityConfiguration(
            @Value("${centinela.security.entra.issuer-uri}") String issuerUri,
            @Value("${centinela.security.entra.audience}") String audience,
            @Value("${centinela.security.entra.jwk-set-uri}") String jwkSetUri) {
        this.issuerUri = issuerUri;
        this.audience = audience;
        this.jwkSetUri = jwkSetUri;
    }

    @Bean
    public SecurityFilterChain filterChain(
            HttpSecurity http,
            JwtDecoder jwtDecoder,
            EntraRolesJwtAuthenticationConverter jwtAuthenticationConverter,
            RestAuthenticationEntryPoint restAuthenticationEntryPoint,
            RestAccessDeniedHandler restAccessDeniedHandler) throws Exception {
        http
                .csrf(csrf -> csrf.disable())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(authorize -> authorize
                        .requestMatchers("/actuator/health/**", "/actuator/info").permitAll()
                        .requestMatchers(HttpMethod.POST, "/api/v1/transactions").hasRole("SERVICE")
                        .requestMatchers(HttpMethod.POST, "/api/v1/verification-documents").hasRole("ANALYST")
                        // Consulta de resultados: la usa el analista para revisar un caso y
                        // el originador para conocer el veredicto de la transaccion que
                        // envio. Ambos roles leen; ninguno escribe por esta via.
                        .requestMatchers(HttpMethod.GET, "/api/v1/transactions/*/analysis")
                        .hasAnyRole("ANALYST", "SERVICE")
                        .requestMatchers(HttpMethod.GET, "/api/v1/cases/*")
                        .hasAnyRole("ANALYST", "SERVICE")
                        .anyRequest().authenticated())
                .exceptionHandling(exceptionHandling -> exceptionHandling
                        .authenticationEntryPoint(restAuthenticationEntryPoint)
                        .accessDeniedHandler(restAccessDeniedHandler))
                .oauth2ResourceServer(oauth2 -> oauth2
                        .jwt(jwt -> jwt
                                .decoder(jwtDecoder)
                                .jwtAuthenticationConverter(jwtAuthenticationConverter)));

        return http.build();
    }

    @Bean
    public JwtDecoder jwtDecoder() {
        NimbusJwtDecoder decoder = NimbusJwtDecoder.withJwkSetUri(jwkSetUri).build();
        OAuth2TokenValidator<Jwt> withIssuer = JwtValidators.createDefaultWithIssuer(issuerUri);
        OAuth2TokenValidator<Jwt> withAudience = new AudienceValidator(audience);
        decoder.setJwtValidator(new DelegatingAudienceAwareValidator(withIssuer, withAudience));
        return decoder;
    }

    @Bean
    public EntraRolesJwtAuthenticationConverter jwtAuthenticationConverter() {
        return new EntraRolesJwtAuthenticationConverter();
    }

    @Bean
    public RestAuthenticationEntryPoint restAuthenticationEntryPoint(ObjectMapper objectMapper) {
        return new RestAuthenticationEntryPoint(objectMapper);
    }

    @Bean
    public RestAccessDeniedHandler restAccessDeniedHandler(ObjectMapper objectMapper) {
        return new RestAccessDeniedHandler(objectMapper);
    }

    /**
     * Combina la validacion por defecto (firma, expiracion, issuer) con la
     * validacion del claim {@code aud}, sin depender de una libreria externa
     * de delegacion para mantener este archivo autocontenido.
     */
    private static final class DelegatingAudienceAwareValidator implements OAuth2TokenValidator<Jwt> {

        private final OAuth2TokenValidator<Jwt> defaultValidator;
        private final OAuth2TokenValidator<Jwt> audienceValidator;

        private DelegatingAudienceAwareValidator(
                OAuth2TokenValidator<Jwt> defaultValidator,
                OAuth2TokenValidator<Jwt> audienceValidator) {
            this.defaultValidator = defaultValidator;
            this.audienceValidator = audienceValidator;
        }

        @Override
        public OAuth2TokenValidatorResult validate(Jwt token) {
            OAuth2TokenValidatorResult defaultResult = defaultValidator.validate(token);
            if (defaultResult.hasErrors()) {
                return defaultResult;
            }
            return audienceValidator.validate(token);
        }
    }

    /** Verifica que el claim {@code aud} contenga el audience esperado. */
    private static final class AudienceValidator implements OAuth2TokenValidator<Jwt> {

        private static final OAuth2Error INVALID_AUDIENCE =
                new OAuth2Error("invalid_token", "The required audience is missing", null);

        private final String expectedAudience;

        private AudienceValidator(String expectedAudience) {
            this.expectedAudience = expectedAudience;
        }

        @Override
        public OAuth2TokenValidatorResult validate(Jwt jwt) {
            List<String> audiences = jwt.getAudience();
            if (audiences != null && audiences.contains(expectedAudience)) {
                return OAuth2TokenValidatorResult.success();
            }
            return OAuth2TokenValidatorResult.failure(INVALID_AUDIENCE);
        }
    }
}
