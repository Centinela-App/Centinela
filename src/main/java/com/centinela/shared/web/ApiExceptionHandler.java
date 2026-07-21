package com.centinela.shared.web;

import com.centinela.documentstorage.application.exception.DocumentStorageUnavailableException;
import com.centinela.documentstorage.application.exception.InvalidVerificationDocumentException;
import com.centinela.transactioningestion.application.exception.StorageUnavailableException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.converter.HttpMessageNotReadableException;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.multipart.support.MissingServletRequestPartException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * Convierte errores de entrada en respuestas seguras, sin stack trace.
 */
@RestControllerAdvice
public class ApiExceptionHandler {

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<ErrorResponse> handleValidation(MethodArgumentNotValidException exception) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(new ErrorResponse("INVALID_REQUEST", "Request validation failed"));
    }

    @ExceptionHandler(HttpMessageNotReadableException.class)
    public ResponseEntity<ErrorResponse> handleUnreadableBody(HttpMessageNotReadableException exception) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(new ErrorResponse("INVALID_REQUEST", "Request body is malformed or contains unknown fields"));
    }

    @ExceptionHandler({InvalidVerificationDocumentException.class, MissingServletRequestPartException.class})
    public ResponseEntity<ErrorResponse> handleInvalidDocument(Exception exception) {
        return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                .body(new ErrorResponse(
                        "INVALID_DOCUMENT",
                        "Verification document is missing or invalid"));
    }

    @ExceptionHandler(DocumentStorageUnavailableException.class)
    public ResponseEntity<ErrorResponse> handleDocumentStorageUnavailable(
            DocumentStorageUnavailableException exception) {
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(new ErrorResponse(
                        "STORAGE_UNAVAILABLE",
                        "Document storage is temporarily unavailable"));
    }

    @ExceptionHandler(StorageUnavailableException.class)
    public ResponseEntity<ErrorResponse> handleStorageUnavailable(StorageUnavailableException exception) {
        return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                .body(new ErrorResponse("STORAGE_UNAVAILABLE", "Transaction storage is temporarily unavailable"));
    }
}
