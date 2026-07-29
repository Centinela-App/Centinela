package com.centinela.documentverification.infrastructure.extraction;

import com.centinela.documentverification.domain.model.DocumentState;
import com.centinela.documentverification.domain.model.ExtractionOutcome;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * El criterio de aceptacion dice: "un documento corrupto o ilegible no interrumpe el
 * flujo". La forma de garantizarlo en codigo es que este extractor <b>nunca lance</b>.
 * Cada prueba alimenta una forma distinta de documento roto y verifica dos cosas: que se
 * devuelve un desenlace y que ese desenlace distingue que fue lo que fallo — porque
 * "vuelva a escanearlo" y "ese formato no se admite" son instrucciones distintas para el
 * analista.
 */
class TextualIdentityDataExtractorTest {

    private final TextualIdentityDataExtractor extractor = new TextualIdentityDataExtractor();

    @Test
    void extracts_the_four_fields_from_a_readable_document() {
        String document = """
                REPÚBLICA DE COLOMBIA
                CÉDULA DE CIUDADANÍA
                Nombres y apellidos: MARIA FERNANDA LOPEZ GOMEZ
                Número de documento: 1.020.345.678
                Fecha de nacimiento: 14/03/1991
                Fecha de vencimiento: 2031-03-14
                """;

        ExtractionOutcome outcome = extractor.extract(
                document.getBytes(StandardCharsets.UTF_8), "text/plain", "cedula.txt");

        assertThat(outcome.state()).isEqualTo(DocumentState.EXTRACTED);
        assertThat(outcome.data().fullName()).isEqualTo("MARIA FERNANDA LOPEZ GOMEZ");
        assertThat(outcome.data().documentNumber()).isEqualTo("1020345678");
        assertThat(outcome.data().birthDate()).isEqualTo(LocalDate.of(1991, 3, 14));
        assertThat(outcome.data().expiryDate()).isEqualTo(LocalDate.of(2031, 3, 14));
        assertThat(outcome.failureReason()).isNull();
    }

    @Test
    void reports_partial_extraction_instead_of_failing_on_an_incomplete_document() {
        // Un documento recortado da lo que tiene. Descartarlo entero obligaria al analista
        // a teclear de nuevo datos que si eran legibles.
        String document = "Nombres y apellidos: JUAN PEREZ\nOtra linea sin interes\n";

        ExtractionOutcome outcome = extractor.extract(
                document.getBytes(StandardCharsets.UTF_8), "text/plain", "parcial.txt");

        assertThat(outcome.state()).isEqualTo(DocumentState.PARTIALLY_EXTRACTED);
        assertThat(outcome.data().fullName()).isEqualTo("JUAN PEREZ");
        assertThat(outcome.data().documentNumber()).isNull();
    }

    @Test
    void reports_a_corrupt_pdf_as_unreadable_without_throwing() {
        byte[] corrupt = "esto no es un PDF aunque diga que lo es".getBytes(StandardCharsets.UTF_8);

        ExtractionOutcome outcome = extractor.extract(corrupt, "application/pdf", "documento.pdf");

        assertThat(outcome.state()).isEqualTo(DocumentState.UNREADABLE);
        assertThat(outcome.failureReason()).contains("firma invalida");
    }

    @Test
    void reports_truncated_pdf_bytes_as_unreadable_without_throwing() {
        // Cabecera valida pero cuerpo destruido: la ruta que si entra a PDFBox.
        byte[] truncated = "%PDF-1.7\n%âãÏÓ\nbasura".getBytes(StandardCharsets.ISO_8859_1);

        ExtractionOutcome outcome = extractor.extract(truncated, "application/pdf", "documento.pdf");

        assertThat(outcome.state()).isEqualTo(DocumentState.UNREADABLE);
        assertThat(outcome.data().isEmpty()).isTrue();
    }

    @Test
    void reports_an_image_as_unsupported_rather_than_pretending_it_is_empty() {
        // Sin reconocimiento optico, una imagen no se puede leer. Decir "sin datos" haria
        // creer que el documento estaba en blanco.
        ExtractionOutcome outcome = extractor.extract(
                new byte[]{(byte) 0x89, 0x50, 0x4E, 0x47}, "image/png", "cedula.png");

        assertThat(outcome.state()).isEqualTo(DocumentState.UNSUPPORTED_FORMAT);
        assertThat(outcome.analystMessage("ruta")).contains("no está soportado");
    }

    @Test
    void reports_an_empty_upload_as_unreadable() {
        assertThat(extractor.extract(new byte[0], "text/plain", "vacio.txt").state())
                .isEqualTo(DocumentState.UNREADABLE);
        assertThat(extractor.extract(null, "text/plain", "nulo.txt").state())
                .isEqualTo(DocumentState.UNREADABLE);
    }

    @Test
    void reports_readable_text_without_identity_fields_as_unreadable() {
        ExtractionOutcome outcome = extractor.extract(
                "Lista de compras: pan, leche, café".getBytes(StandardCharsets.UTF_8),
                "text/plain", "compras.txt");

        assertThat(outcome.state()).isEqualTo(DocumentState.UNREADABLE);
        assertThat(outcome.failureReason()).contains("no se reconocio ningun campo");
    }

    @Test
    void infers_the_format_from_content_when_the_declared_type_is_wrong() {
        // Los clientes mienten sobre el content-type. El contenido manda.
        String document = "Cédula de ciudadanía: 1020345678\n";

        ExtractionOutcome outcome = extractor.extract(
                document.getBytes(StandardCharsets.UTF_8), "application/octet-stream", "sin-extension");

        assertThat(outcome.state()).isEqualTo(DocumentState.PARTIALLY_EXTRACTED);
        assertThat(outcome.data().documentNumber()).isEqualTo("1020345678");
    }

    @Test
    void every_outcome_carries_a_message_the_analyst_can_act_on() {
        for (DocumentState state : DocumentState.values()) {
            ExtractionOutcome outcome = new ExtractionOutcome(state, null, null, "test");
            assertThat(outcome.analystMessage("ruta/al/blob")).isNotBlank();
        }
    }
}
