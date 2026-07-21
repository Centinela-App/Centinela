package com.centinela.documentstorage.application.command;

import java.util.Objects;

/**
 * Datos de entrada independientes de HTTP para almacenar un documento.
 */
public record StoreVerificationDocumentCommand(String originalFilename, byte[] content) {

    public StoreVerificationDocumentCommand {
        content = Objects.requireNonNull(content, "content is required").clone();
    }

    @Override
    public byte[] content() {
        return content.clone();
    }
}
