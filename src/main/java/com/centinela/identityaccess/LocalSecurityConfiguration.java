package com.centinela.identityaccess;

import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;

/**
 * Cadena de seguridad del perfil {@code local}: sin autenticacion.
 *
 * <p><b>Por que existe.</b> El entorno local (docker-compose) no tiene Entra ID: no hay
 * emisor de tokens contra el que validar, y exigir JWT alli obligaria a cada
 * desarrollador a montar un IdP falso para probar un endpoint. El perfil {@code test} ya
 * asume esta postura con valores ficticios; este perfil la asume para ejecucion
 * interactiva.
 *
 * <p><b>Salvaguardas, porque una cadena permitAll es un arma cargada:</b>
 *
 * <ul>
 *   <li>Solo se activa con el perfil {@code local}, que ningun artefacto de despliegue
 *       de Azure establece: los scripts de despliegue no fijan
 *       {@code SPRING_PROFILES_ACTIVE=local} en ninguna ruta de codigo.</li>
 *   <li>{@link SecurityConfiguration} lleva {@code @Profile("!local")}: no pueden
 *       coexistir dos cadenas y el arranque falla si ambas intentaran registrarse.</li>
 *   <li>El arranque emite un aviso inconfundible. Si ese texto aparece en los registros
 *       de un contenedor en Azure, algo esta gravemente mal configurado y debe tratarse
 *       como incidente, no como curiosidad.</li>
 * </ul>
 */
@Configuration
@EnableWebSecurity
@Profile("local")
public class LocalSecurityConfiguration {

    private static final Logger log = LoggerFactory.getLogger(LocalSecurityConfiguration.class);

    @PostConstruct
    void warnLoudly() {
        log.warn("==============================================================");
        log.warn("  SEGURIDAD DESACTIVADA — perfil 'local'");
        log.warn("  Todos los endpoints aceptan peticiones sin autenticacion.");
        log.warn("  Si este mensaje aparece en Azure, es un incidente.");
        log.warn("==============================================================");
    }

    @Bean
    public SecurityFilterChain localFilterChain(HttpSecurity http) throws Exception {
        http
                .csrf(csrf -> csrf.disable())
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(authorize -> authorize.anyRequest().permitAll());
        return http.build();
    }
}
