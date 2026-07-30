package com.centinela.documentverification.application.port.out;

import java.util.Optional;

/** Lectura del contenido de un documento ya almacenado en el contenedor de objetos. */
public interface DocumentContentReaderPort {

    /**
     * @return los bytes del documento, o vacio si el blob no existe
     */
    Optional<byte[]> read(String blobPath);
}
