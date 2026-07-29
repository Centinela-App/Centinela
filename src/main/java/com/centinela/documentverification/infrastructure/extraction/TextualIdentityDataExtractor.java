package com.centinela.documentverification.infrastructure.extraction;

import com.centinela.documentverification.application.port.out.IdentityDataExtractorPort;
import com.centinela.documentverification.domain.model.ExtractedIdentityData;
import com.centinela.documentverification.domain.model.ExtractionOutcome;
import org.apache.pdfbox.Loader;
import org.apache.pdfbox.pdmodel.PDDocument;
import org.apache.pdfbox.text.PDFTextStripper;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Extractor documental ejecutado dentro del propio componente, sin servicio externo.
 *
 * <p>Es el <b>plan alternativo</b> que contempla el enunciado para cuando el servicio
 * administrado de reconocimiento documental no esta disponible en la suscripcion. Procesa
 * PDF con capa de texto y archivos de texto plano.
 *
 * <p><b>Limitacion declarada, no disimulada.</b> No hace OCR: un PDF escaneado sin capa de
 * texto, o una imagen, no producen datos. Ese desenlace se comunica como
 * {@code UNREADABLE} o {@code UNSUPPORTED_FORMAT} con un mensaje que le dice al analista
 * exactamente que hacer, en lugar de devolver campos vacios que parezcan un documento
 * legitimo sin datos.
 *
 * <p>Nunca lanza: cualquier fallo se convierte en un desenlace. Es lo que garantiza que un
 * archivo corrupto no interrumpa el procesamiento del lote.
 */
public final class TextualIdentityDataExtractor implements IdentityDataExtractorPort {

    public static final String ENGINE = "local-textual-v1";

    private static final int MAX_TEXT_LENGTH = 200_000;

    private static final List<String> PDF_TYPES = List.of("application/pdf");
    private static final List<String> TEXT_TYPES = List.of("text/plain", "text/csv");
    private static final List<String> IMAGE_PREFIXES = List.of("image/");

    /** Firma de PDF: los cuatro primeros bytes de un archivo valido son "%PDF". */
    private static final byte[] PDF_MAGIC = {0x25, 0x50, 0x44, 0x46};

    private static final Pattern NAME = Pattern.compile(
            "(?im)^\\s*(?:nombres?\\s+y\\s+apellidos|nombre\\s+completo|nombres?|apellidos\\s+y\\s+nombres|full\\s*name|surname\\s*/\\s*name)\\s*[:\\-]\\s*(.+)$");
    private static final Pattern DOCUMENT_NUMBER = Pattern.compile(
            "(?im)^\\s*(?:n[uú]mero\\s+de\\s+(?:documento|identificaci[oó]n)|c[eé]dula(?:\\s+de\\s+ciudadan[ií]a)?|nuip|document\\s*(?:number|no\\.?)|id\\s*(?:number|no\\.?))\\s*[:\\-]\\s*([0-9][0-9.\\s-]{4,24})\\s*$");
    private static final Pattern BIRTH_DATE = Pattern.compile(
            "(?im)^\\s*(?:fecha\\s+de\\s+nacimiento|nacimiento|date\\s+of\\s+birth|birth\\s*date)\\s*[:\\-]\\s*(.+)$");
    private static final Pattern EXPIRY_DATE = Pattern.compile(
            "(?im)^\\s*(?:fecha\\s+de\\s+(?:expiraci[oó]n|vencimiento|caducidad)|expiry\\s*date|valid\\s+until)\\s*[:\\-]\\s*(.+)$");

    private static final List<DateTimeFormatter> DATE_FORMATS = List.of(
            DateTimeFormatter.ISO_LOCAL_DATE,
            DateTimeFormatter.ofPattern("dd/MM/uuuu", Locale.ROOT),
            DateTimeFormatter.ofPattern("d/M/uuuu", Locale.ROOT),
            DateTimeFormatter.ofPattern("dd-MM-uuuu", Locale.ROOT),
            DateTimeFormatter.ofPattern("uuuu/MM/dd", Locale.ROOT));

    @Override
    public String engineName() {
        return ENGINE;
    }

    @Override
    public ExtractionOutcome extract(byte[] content, String contentType, String fileName) {
        if (content == null || content.length == 0) {
            return ExtractionOutcome.unreadable("El documento esta vacio.", ENGINE);
        }

        Format format = resolveFormat(content, contentType, fileName);
        return switch (format) {
            case PDF -> fromPdf(content);
            case TEXT -> fromText(new String(content, StandardCharsets.UTF_8));
            case UNSUPPORTED -> ExtractionOutcome.unsupportedFormat(
                    contentType == null ? "desconocido" : contentType, ENGINE);
        };
    }

    private ExtractionOutcome fromPdf(byte[] content) {
        // La comprobacion de firma separa dos desenlaces que exigen acciones distintas del
        // analista: "esto no es un PDF" y "es un PDF pero no tiene texto".
        if (!startsWith(content, PDF_MAGIC)) {
            return ExtractionOutcome.unreadable(
                    "El archivo se declaro como PDF pero su contenido no lo es (firma invalida). "
                            + "Probablemente esta corrupto o truncado.", ENGINE);
        }

        try (PDDocument document = Loader.loadPDF(content)) {
            if (document.isEncrypted()) {
                return ExtractionOutcome.unreadable(
                        "El PDF esta protegido con contrasena y no puede leerse.", ENGINE);
            }
            PDFTextStripper stripper = new PDFTextStripper();
            String text = stripper.getText(document);
            if (text == null || text.isBlank()) {
                return ExtractionOutcome.unreadable(
                        "El PDF no contiene texto recuperable. Si es un escaneo, se requiere un "
                                + "motor con reconocimiento optico de caracteres.", ENGINE);
            }
            return fromText(text);
        } catch (Exception exception) {
            return ExtractionOutcome.unreadable(
                    "El PDF no pudo abrirse: " + exception.getMessage(), ENGINE);
        }
    }

    private ExtractionOutcome fromText(String rawText) {
        String text = rawText.length() > MAX_TEXT_LENGTH ? rawText.substring(0, MAX_TEXT_LENGTH) : rawText;

        ExtractedIdentityData data = new ExtractedIdentityData(
                firstGroup(NAME, text).map(TextualIdentityDataExtractor::cleanName).orElse(null),
                firstGroup(DOCUMENT_NUMBER, text).map(TextualIdentityDataExtractor::cleanNumber).orElse(null),
                firstGroup(BIRTH_DATE, text).flatMap(TextualIdentityDataExtractor::parseDate).orElse(null),
                firstGroup(EXPIRY_DATE, text).flatMap(TextualIdentityDataExtractor::parseDate).orElse(null),
                null);

        if (data.isEmpty()) {
            return ExtractionOutcome.unreadable(
                    "Se leyo el documento pero no se reconocio ningun campo de identidad. "
                            + "Verifique que corresponda a un documento de identidad.", ENGINE);
        }
        return ExtractionOutcome.success(data, ENGINE);
    }

    private Format resolveFormat(byte[] content, String contentType, String fileName) {
        String type = contentType == null ? "" : contentType.toLowerCase(Locale.ROOT).trim();
        String name = fileName == null ? "" : fileName.toLowerCase(Locale.ROOT);

        if (IMAGE_PREFIXES.stream().anyMatch(type::startsWith)) {
            return Format.UNSUPPORTED;
        }
        if (PDF_TYPES.contains(type) || name.endsWith(".pdf")) {
            return Format.PDF;
        }
        if (TEXT_TYPES.contains(type) || name.endsWith(".txt")) {
            return Format.TEXT;
        }
        // Tipo no declarado o poco fiable: se decide por el contenido real.
        if (startsWith(content, PDF_MAGIC)) {
            return Format.PDF;
        }
        return looksLikeText(content) ? Format.TEXT : Format.UNSUPPORTED;
    }

    /** Heuristica conservadora: si hay bytes de control fuera de los saltos de linea, no es texto. */
    private static boolean looksLikeText(byte[] content) {
        int sampled = Math.min(content.length, 1024);
        for (int index = 0; index < sampled; index++) {
            int value = content[index] & 0xFF;
            boolean isPrintable = value >= 0x20 || value == '\n' || value == '\r' || value == '\t';
            if (!isPrintable) {
                return false;
            }
        }
        return true;
    }

    private static boolean startsWith(byte[] content, byte[] prefix) {
        if (content.length < prefix.length) {
            return false;
        }
        for (int index = 0; index < prefix.length; index++) {
            if (content[index] != prefix[index]) {
                return false;
            }
        }
        return true;
    }

    private static Optional<String> firstGroup(Pattern pattern, String text) {
        Matcher matcher = pattern.matcher(text);
        return matcher.find() ? Optional.ofNullable(matcher.group(1)).map(String::trim) : Optional.empty();
    }

    private static String cleanName(String value) {
        return value.replaceAll("\\s+", " ").trim();
    }

    private static String cleanNumber(String value) {
        return value.replaceAll("[^0-9]", "");
    }

    private static Optional<LocalDate> parseDate(String value) {
        String candidate = value.trim().split("\\s+")[0];
        for (DateTimeFormatter format : DATE_FORMATS) {
            try {
                return Optional.of(LocalDate.parse(candidate, format));
            } catch (RuntimeException ignored) {
                // Se prueba el siguiente formato.
            }
        }
        return Optional.empty();
    }

    private enum Format { PDF, TEXT, UNSUPPORTED }
}
