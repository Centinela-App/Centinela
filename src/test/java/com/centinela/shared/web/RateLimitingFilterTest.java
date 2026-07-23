package com.centinela.shared.web;

import jakarta.servlet.ServletException;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.io.IOException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * TEST-S2-008: la API responde 429 cuando un origen excede el limite de tasa, y no
 * deja pasar la peticion excedente. Verifica ademas el aislamiento por origen, el
 * relleno con el paso del tiempo y que otros endpoints no se ven afectados.
 */
class RateLimitingFilterTest {

    private static final String TRANSACTIONS_PATH = "/api/v1/transactions";

    @Test
    void should_return_429_after_exceeding_the_limit_for_the_same_origin() throws Exception {
        // Capacidad 2, sin relleno relevante (reloj fijo): la 3a peticion excede.
        RateLimitingFilter filter = new RateLimitingFilter(2, 60_000L, fixedClock());

        assertEquals(200, invoke(filter, "203.0.113.7").getStatus(), "1a peticion permitida");
        assertEquals(200, invoke(filter, "203.0.113.7").getStatus(), "2a peticion permitida");

        MockHttpServletResponse third = invoke(filter, "203.0.113.7");
        assertEquals(429, third.getStatus(), "3a peticion excede el limite");
        assertTrue(third.getContentAsString().contains("RATE_LIMITED"));
        assertNotNull(third.getHeader("Retry-After"));
    }

    @Test
    void should_not_forward_the_request_when_rate_limited() throws Exception {
        RateLimitingFilter filter = new RateLimitingFilter(1, 60_000L, fixedClock());

        MockFilterChain firstChain = new MockFilterChain();
        filter.doFilter(request("198.51.100.1"), new MockHttpServletResponse(), firstChain);
        assertNotNull(firstChain.getRequest(), "La 1a peticion llega a la cadena");

        MockFilterChain blockedChain = new MockFilterChain();
        MockHttpServletResponse blocked = new MockHttpServletResponse();
        filter.doFilter(request("198.51.100.1"), blocked, blockedChain);
        assertEquals(429, blocked.getStatus());
        assertNull(blockedChain.getRequest(), "La peticion excedente NO se reenvia a la cadena");
    }

    @Test
    void should_track_limits_per_origin() throws Exception {
        RateLimitingFilter filter = new RateLimitingFilter(1, 60_000L, fixedClock());

        assertEquals(200, invoke(filter, "10.0.0.1").getStatus());
        assertEquals(429, invoke(filter, "10.0.0.1").getStatus(), "El primer origen ya agoto su cupo");
        assertEquals(200, invoke(filter, "10.0.0.2").getStatus(), "Otro origen tiene su propio cupo");
    }

    @Test
    void should_prefer_x_forwarded_for_origin() throws Exception {
        RateLimitingFilter filter = new RateLimitingFilter(1, 60_000L, fixedClock());

        MockHttpServletRequest first = request("10.0.0.9");
        first.addHeader("X-Forwarded-For", "70.70.70.70, 10.0.0.9");
        MockHttpServletResponse firstResponse = new MockHttpServletResponse();
        filter.doFilter(first, firstResponse, new MockFilterChain());
        assertEquals(200, firstResponse.getStatus());

        // Mismo cliente real (primer hop del XFF) aunque cambie el remoteAddr del proxy.
        MockHttpServletRequest second = request("10.0.0.10");
        second.addHeader("X-Forwarded-For", "70.70.70.70, 10.0.0.10");
        MockHttpServletResponse secondResponse = new MockHttpServletResponse();
        filter.doFilter(second, secondResponse, new MockFilterChain());
        assertEquals(429, secondResponse.getStatus());
    }

    @Test
    void should_refill_tokens_over_time() throws Exception {
        MutableClock clock = new MutableClock(Instant.parse("2026-07-18T00:00:00Z"));
        // Capacidad 1 que se rellena por completo cada 1000 ms.
        RateLimitingFilter filter = new RateLimitingFilter(1, 1_000L, clock);

        assertEquals(200, invoke(filter, "10.1.1.1").getStatus());
        assertEquals(429, invoke(filter, "10.1.1.1").getStatus());

        clock.advance(Duration.ofMillis(1_100)); // pasa mas de una ventana de relleno
        assertEquals(200, invoke(filter, "10.1.1.1").getStatus(), "Tras el relleno vuelve a permitir");
    }

    @Test
    void should_not_rate_limit_other_paths() throws ServletException, IOException {
        RateLimitingFilter filter = new RateLimitingFilter(1, 60_000L, fixedClock());

        MockHttpServletRequest healthGet = new MockHttpServletRequest("GET", "/actuator/health");
        healthGet.setRemoteAddr("10.2.2.2");
        MockFilterChain chain = new MockFilterChain();
        filter.doFilter(healthGet, new MockHttpServletResponse(), chain);
        assertNotNull(chain.getRequest(), "GET /actuator/health no debe limitarse");

        // Muchas peticiones a otro path del mismo origen: nunca 429.
        for (int i = 0; i < 5; i++) {
            MockHttpServletRequest other = new MockHttpServletRequest("POST", "/api/v1/verification-documents");
            other.setRemoteAddr("10.2.2.2");
            MockHttpServletResponse response = new MockHttpServletResponse();
            filter.doFilter(other, response, new MockFilterChain());
            assertEquals(200, response.getStatus());
        }
    }

    private static MockHttpServletResponse invoke(RateLimitingFilter filter, String remoteAddr)
            throws ServletException, IOException {
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request(remoteAddr), response, new MockFilterChain());
        return response;
    }

    private static MockHttpServletRequest request(String remoteAddr) {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", TRANSACTIONS_PATH);
        request.setRemoteAddr(remoteAddr);
        return request;
    }

    private static Clock fixedClock() {
        return Clock.fixed(Instant.parse("2026-07-18T00:00:00Z"), ZoneOffset.UTC);
    }

    /** Reloj avanzable para probar el relleno del bucket. */
    private static final class MutableClock extends Clock {

        private Instant instant;

        private MutableClock(Instant instant) {
            this.instant = instant;
        }

        private void advance(Duration duration) {
            this.instant = this.instant.plus(duration);
        }

        @Override
        public ZoneOffset getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(java.time.ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return instant;
        }

        @Override
        public long millis() {
            return instant.toEpochMilli();
        }
    }
}
