package com.centinela.shared.web;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.Ordered;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Clock;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Limitacion de tasa por origen para la ingesta de transacciones (ISS-S2-006).
 *
 * <p>Sin este control, un origen puede saturar la API y disparar una ejecucion del
 * motor de scoring por cada peticion, consumiendo credito. El filtro aplica un
 * <b>token bucket</b> por IP de origen exclusivamente sobre {@code POST
 * /api/v1/transactions} y responde {@code 429 Too Many Requests} al exceder el
 * limite. Corre antes de la seguridad para frenar tambien avalanchas no autenticadas.
 *
 * <p>Los limites son configurables sin recompilar (App Settings / variables de
 * entorno): {@code centinela.ratelimit.capacity} y
 * {@code centinela.ratelimit.refill-period-ms}. Implementacion propia y autocontenida
 * (sin dependencias externas) para no acoplar el arranque a una libreria de terceros.
 */
@Component
public class RateLimitingFilter extends OncePerRequestFilter implements Ordered {

    private static final String RATE_LIMITED_BODY =
            "{\"code\":\"RATE_LIMITED\",\"message\":\"Too many requests from this origin\"}";
    private static final String TRANSACTIONS_PATH = "/api/v1/transactions";
    private static final String X_FORWARDED_FOR = "X-Forwarded-For";

    private final int capacity;
    private final long refillPeriodMillis;
    private final Clock clock;
    private final ConcurrentHashMap<String, TokenBucket> buckets = new ConcurrentHashMap<>();

    @Autowired
    public RateLimitingFilter(
            @Value("${centinela.ratelimit.capacity:120}") int capacity,
            @Value("${centinela.ratelimit.refill-period-ms:60000}") long refillPeriodMillis) {
        this(capacity, refillPeriodMillis, Clock.systemUTC());
    }

    RateLimitingFilter(int capacity, long refillPeriodMillis, Clock clock) {
        if (capacity <= 0) {
            throw new IllegalArgumentException("centinela.ratelimit.capacity must be > 0");
        }
        if (refillPeriodMillis <= 0) {
            throw new IllegalArgumentException("centinela.ratelimit.refill-period-ms must be > 0");
        }
        this.capacity = capacity;
        this.refillPeriodMillis = refillPeriodMillis;
        this.clock = clock;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !(HttpMethod.POST.matches(request.getMethod())
                && TRANSACTIONS_PATH.equals(request.getRequestURI()));
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {

        TokenBucket bucket = buckets.computeIfAbsent(
                clientKey(request),
                key -> new TokenBucket(capacity, refillPeriodMillis, clock));

        if (bucket.tryConsume()) {
            filterChain.doFilter(request, response);
        } else {
            rejectTooManyRequests(response);
        }
    }

    private static String clientKey(HttpServletRequest request) {
        String forwardedFor = request.getHeader(X_FORWARDED_FOR);
        if (forwardedFor != null && !forwardedFor.isBlank()) {
            return forwardedFor.split(",", 2)[0].trim();
        }
        return request.getRemoteAddr();
    }

    private void rejectTooManyRequests(HttpServletResponse response) throws IOException {
        response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setHeader(HttpHeaders.RETRY_AFTER, Long.toString(Math.max(1, refillPeriodMillis / 1000)));
        response.getWriter().write(RATE_LIMITED_BODY);
    }

    @Override
    public int getOrder() {
        // Antes de la cadena de Spring Security para frenar avalanchas no autenticadas,
        // pero DESPUES de TracePropagationFilter, que reclama HIGHEST_PRECEDENCE.
        //
        // El +1 no es cosmetico. Ambos filtros declaraban el mismo orden y el desempate
        // quedaba al azar del contenedor: si este corria primero, una peticion rechazada
        // con 429 salia SIN traza — exactamente la peticion que mas interesa poder
        // rastrear cuando un origen esta saturando la API. Un empate de orden entre
        // filtros no falla: se comporta distinto entre arranques, que es peor.
        return Ordered.HIGHEST_PRECEDENCE + 1;
    }

    /**
     * Token bucket simple y thread-safe. Se rellena de forma continua a razon de
     * {@code capacity} tokens por {@code refillPeriodMillis}.
     */
    private static final class TokenBucket {

        private final int capacity;
        private final double tokensPerMilli;
        private final Clock clock;
        private double tokens;
        private long lastRefillMillis;

        private TokenBucket(int capacity, long refillPeriodMillis, Clock clock) {
            this.capacity = capacity;
            this.tokensPerMilli = (double) capacity / (double) refillPeriodMillis;
            this.clock = clock;
            this.tokens = capacity;
            this.lastRefillMillis = clock.millis();
        }

        synchronized boolean tryConsume() {
            refill();
            if (tokens >= 1.0d) {
                tokens -= 1.0d;
                return true;
            }
            return false;
        }

        private void refill() {
            long now = clock.millis();
            long elapsed = now - lastRefillMillis;
            if (elapsed > 0) {
                tokens = Math.min(capacity, tokens + elapsed * tokensPerMilli);
                lastRefillMillis = now;
            }
        }
    }
}
