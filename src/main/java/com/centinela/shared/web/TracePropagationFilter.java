package com.centinela.shared.web;

import com.centinela.shared.trace.TraceContext;
import com.centinela.shared.trace.TraceContextHolder;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * Establece el contexto de traza al inicio de cada peticion y lo desmonta al final.
 *
 * <p>Es el primer eslabon del recorrido que el enunciado exige poder reconstruir. Si la
 * peticion trae {@code traceparent} — como hace la app de pruebas, o cualquier cliente
 * instrumentado — Centinela <b>continua</b> esa traza en lugar de abrir una nueva, de
 * modo que el recorrido incluye tambien al originador. Si no lo trae, abre la traza aqui.
 *
 * <p>Se ejecuta con la maxima precedencia, antes que el limitador de tasa y que la cadena
 * de seguridad: una peticion rechazada con {@code 429} o {@code 401} tambien debe quedar
 * trazada. Un fallo que no aparece en la traza es exactamente el que no se puede
 * diagnosticar.
 *
 * <p>El {@code traceparent} se devuelve en la respuesta para que el cliente pueda mostrar
 * el identificador y buscar la traza sin adivinarlo.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class TracePropagationFilter extends OncePerRequestFilter {

    /** Claves publicadas en el MDC para que cada linea de log quede correlacionada. */
    public static final String MDC_TRACE_ID = "traceId";
    public static final String MDC_SPAN_ID = "spanId";

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {

        TraceContext context = TraceContext.parseOrNewRoot(request.getHeader(TraceContext.HEADER));

        TraceContextHolder.set(context);
        MDC.put(MDC_TRACE_ID, context.traceId());
        MDC.put(MDC_SPAN_ID, context.spanId());
        response.setHeader(TraceContext.HEADER, context.toTraceparent());

        try {
            filterChain.doFilter(request, response);
        } finally {
            // Los hilos del contenedor se reutilizan: un contexto olvidado atribuiria el
            // trabajo de la siguiente peticion a la traza de esta.
            MDC.remove(MDC_TRACE_ID);
            MDC.remove(MDC_SPAN_ID);
            TraceContextHolder.clear();
        }
    }
}
