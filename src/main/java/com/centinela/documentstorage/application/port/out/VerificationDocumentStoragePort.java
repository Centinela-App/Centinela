package com.centinela.documentstorage.application.port.out;

import com.centinela.documentstorage.domain.model.VerificationDocument;

import java.time.Instant;

/**
 * Puerto de salida para conservar documentos sin exponer tipos de Azure.
 */
@FunctionalInterface
public interface VerificationDocumentStoragePort {

    void store(VerificationDocument document, Instant receivedAt);
}
