package com.centinela.documentverification.application.port.out;

import com.centinela.documentverification.domain.model.ExtractionOutcome;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

/**
 * Registro de los documentos adjuntos a un caso y del desenlace de su extraccion.
 *
 * <p>Es lo que hace que el documento quede "en un estado consultable" sin importar como
 * termine el intento.
 */
public interface VerificationDocumentRegistryPort {

    /**
     * Deja constancia de la carga antes de intentar nada.
     *
     * <p>Se escribe primero a proposito: si el proceso muere durante la extraccion, el
     * documento ya esta registrado como {@code RECEIVED} y el siguiente ciclo lo recoge.
     * Registrar despues perderia el rastro justo en el caso que mas importa.
     *
     * @return identificador del registro, o vacio si no existe un caso para esa transaccion
     */
    Optional<Long> registerReceived(
            String transactionId, String blobPath, String contentType, Instant receivedAt);

    /** Documentos pendientes de extraccion, del mas antiguo al mas reciente. */
    List<PendingDocument> findPending(int limit);

    /** Escribe el desenlace y notifica al analista en la misma transaccion. */
    void recordOutcome(Long documentId, ExtractionOutcome outcome, Instant processedAt);

    /** Proyeccion minima para procesar un documento pendiente. */
    record PendingDocument(Long documentId, Long caseId, String blobPath, String contentType) {
    }
}
