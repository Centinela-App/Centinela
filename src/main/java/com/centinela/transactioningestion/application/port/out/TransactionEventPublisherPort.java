package com.centinela.transactioningestion.application.port.out;

import com.centinela.transactioningestion.domain.model.Transaction;

import java.time.Instant;

/**
 * Puerto de salida para publicar el evento {@code transaction-event-v1} tras
 * persistir una transaccion cruda.
 *
 * <p>La API publica el evento para <b>notificar la ocurrencia</b> de la
 * transaccion (API &rarr; Event Grid &rarr; Function) sin esperar el resultado del
 * scoring. Este puerto se expresa en tipos de dominio: no conoce Event Grid, el
 * nombre del contenedor ni la ruta fisica del blob; el adaptador de infraestructura
 * arma el contrato {@code com.centinela.shared.event.TransactionEvent}.
 *
 * <p>Recibe el mismo instante de recepcion usado por el puerto de almacenamiento,
 * de modo que la ubicacion del JSON crudo publicada en el evento coincida con la
 * ruta bajo la que la transaccion quedo persistida.
 */
@FunctionalInterface
public interface TransactionEventPublisherPort {

    /**
     * Publica el evento de la transaccion recien persistida.
     *
     * @param transaction transaccion cruda ya conservada
     * @param receivedAt  instante de recepcion UTC (el mismo usado al persistir)
     * @throws PublicationFailedException si el evento no pudo publicarse; el caso de
     *                                    uso la propaga para no afirmar un exito falso
     */
    void publish(Transaction transaction, Instant receivedAt);

    /**
     * Falla de publicacion del evento. Politica acordada: <b>fallar la peticion</b>
     * (propagar) en lugar de responder un acuse cuando el evento no se publico. El
     * cliente puede reintentar; la escritura del blob es idempotente (sobrescribe la
     * misma ruta por {@code transactionId}), por lo que un reintento re-publica sin
     * duplicar datos de negocio.
     */
    class PublicationFailedException extends RuntimeException {

        public PublicationFailedException(String message, Throwable cause) {
            super(message, cause);
        }
    }
}
