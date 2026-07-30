package com.centinela.scoring.domain.model;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * El contexto de traza entra por una cabecera HTTP publica: es entrada no confiable que
 * atraviesa cuatro procesos. Estas pruebas fijan la propiedad que hace utilizable la
 * traza distribuida (el {@code traceId} sobrevive los saltos) y la que impide que la
 * telemetria tumbe el negocio (un valor corrupto degrada, no lanza).
 */
class TraceContextTest {

    private static final String VALID = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01";

    @Test
    void parses_a_valid_traceparent() {
        TraceContext context = TraceContext.parse(VALID).orElseThrow();

        assertThat(context.traceId()).isEqualTo("4bf92f3577b34da6a3ce929d0e0e4736");
        assertThat(context.spanId()).isEqualTo("00f067aa0ba902b7");
        assertThat(context.sampled()).isTrue();
        assertThat(context.toTraceparent()).isEqualTo(VALID);
    }

    @Test
    void child_span_keeps_the_trace_and_renews_the_span() {
        TraceContext parent = TraceContext.parse(VALID).orElseThrow();

        TraceContext child = parent.childSpan();

        assertThat(child.traceId()).isEqualTo(parent.traceId());
        assertThat(child.spanId()).isNotEqualTo(parent.spanId());
    }

    @Test
    void rejects_malformed_values_without_throwing() {
        assertThat(TraceContext.parse(null)).isEmpty();
        assertThat(TraceContext.parse("")).isEmpty();
        assertThat(TraceContext.parse("not-a-traceparent")).isEmpty();
        assertThat(TraceContext.parse("01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")).isEmpty();
        assertThat(TraceContext.parse("00-4bf92f3577b34da6a3ce929d0e0e473-00f067aa0ba902b7-01")).isEmpty();
    }

    @Test
    void rejects_the_all_zero_identifiers_forbidden_by_the_specification() {
        assertThat(TraceContext.parse("00-" + "0".repeat(32) + "-00f067aa0ba902b7-01")).isEmpty();
        assertThat(TraceContext.parse("00-4bf92f3577b34da6a3ce929d0e0e4736-" + "0".repeat(16) + "-01")).isEmpty();
    }

    @Test
    void degrades_to_a_new_trace_instead_of_failing() {
        String recovered = TraceContext.parseOrNewRoot("garbage").toTraceparent();

        assertThat(TraceContext.isValid(recovered)).isTrue();
        assertThat(recovered).isNotEqualTo(VALID);
    }

    @Test
    void new_roots_do_not_collide() {
        assertThat(TraceContext.newRoot().traceId()).isNotEqualTo(TraceContext.newRoot().traceId());
    }
}
