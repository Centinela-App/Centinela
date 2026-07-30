package com.centinela.caseexplanation.application.port.out;

import java.time.Instant;
import java.util.List;

/**
 * Acceso a los casos que esperan explicacion.
 *
 * <p>El explicador descubre trabajo <b>consultando el estado</b>, no escuchando una cola.
 * Es una decision deliberada: el requisito dice que con el explicador detenido los casos
 * siguen abriendose y que, al restablecerlo, las explicaciones pendientes se generan. Con
 * una cola habria que garantizar que ningun mensaje se pierda mientras el consumidor no
 * existe; consultando {@code explanation_state = 'PENDING'} la recuperacion del backlog es
 * una consecuencia del modelo de datos, no un mecanismo aparte que pueda fallar.
 */
public interface PendingExplanationPort {

    /** Casos pendientes, del mas antiguo al mas reciente. */
    List<PendingCase> findPending(int limit);

    /** Escribe la explicacion y marca el caso como explicado, en una sola transaccion. */
    void attachExplanation(Long caseId, String explanation, Instant generatedAt);

    /**
     * Registra un intento fallido. Al alcanzar {@code maxAttempts} el caso pasa a
     * {@code FAILED} y deja de reintentarse, para que un caso irreparable no consuma el
     * ciclo indefinidamente.
     */
    void recordFailure(Long caseId, int maxAttempts, String reason);

    /** Proyeccion minima necesaria para explicar un caso. */
    record PendingCase(Long caseId, String transactionId, String traceparent, int attempts) {
    }
}
