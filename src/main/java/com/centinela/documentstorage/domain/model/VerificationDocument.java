package com.centinela.documentstorage.domain.model;

import java.util.Objects;

/**
 * Documento tecnico listo para persistirse con un nombre fisico seguro.
 */
public record VerificationDocument(String documentId, String storedFilename, byte[] content) {

    public VerificationDocument {
        documentId = requireText(documentId, "documentId");
        storedFilename = requireText(storedFilename, "storedFilename");
        rejectPathSeparators(documentId, "documentId");
        rejectPathSeparators(storedFilename, "storedFilename");
        content = Objects.requireNonNull(content, "content is required").clone();

        if (storedFilename.equals(".") || storedFilename.equals("..")) {
            throw new IllegalArgumentException("storedFilename is invalid");
        }
        if (content.length == 0) {
            throw new IllegalArgumentException("content must not be empty");
        }
    }

    @Override
    public byte[] content() {
        return content.clone();
    }

    private static void rejectPathSeparators(String value, String field) {
        if (value.indexOf('/') >= 0 || value.indexOf('\\') >= 0) {
            throw new IllegalArgumentException(field + " must not contain path separators");
        }
    }

    private static String requireText(String value, String field) {
        Objects.requireNonNull(value, field + " is required");
        if (value.isBlank()) {
            throw new IllegalArgumentException(field + " must not be blank");
        }
        return value;
    }
}
