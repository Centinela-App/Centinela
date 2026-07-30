package com.centinela.documentverification.domain.model;

import java.time.LocalDate;
import java.util.Optional;

/**
 * Datos estructurados extraidos de un documento de identidad.
 *
 * <p>Todos los campos son opcionales por diseno. Un documento real puede estar arrugado,
 * mal escaneado o recortado: exigir que los cuatro campos existan convertiria cualquier
 * imperfeccion en un fallo total, cuando lo util para el analista es recibir lo que si se
 * pudo leer y saber que falta.
 */
public record ExtractedIdentityData(
        String fullName,
        String documentNumber,
        LocalDate birthDate,
        LocalDate expiryDate,
        Double confidence) {

    public static ExtractedIdentityData empty() {
        return new ExtractedIdentityData(null, null, null, null, null);
    }

    public Optional<String> name() {
        return Optional.ofNullable(fullName).filter(value -> !value.isBlank());
    }

    public Optional<String> number() {
        return Optional.ofNullable(documentNumber).filter(value -> !value.isBlank());
    }

    /** Campos minimos para contrastar el documento con el titular de la cuenta. */
    public boolean isComplete() {
        return name().isPresent() && number().isPresent() && birthDate != null;
    }

    public boolean isEmpty() {
        return name().isEmpty() && number().isEmpty() && birthDate == null && expiryDate == null;
    }

    /**
     * Estado que corresponde a lo extraido.
     *
     * <p>La regla vive aqui, junto a los datos, para que no pueda existir una fila marcada
     * {@code EXTRACTED} con todos los campos vacios.
     */
    public DocumentState resultingState() {
        if (isEmpty()) {
            return DocumentState.UNREADABLE;
        }
        return isComplete() ? DocumentState.EXTRACTED : DocumentState.PARTIALLY_EXTRACTED;
    }
}
