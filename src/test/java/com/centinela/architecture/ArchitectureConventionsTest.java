package com.centinela.architecture;

import com.tngtech.archunit.core.importer.ImportOption;
import com.tngtech.archunit.junit.AnalyzeClasses;
import com.tngtech.archunit.junit.ArchTest;
import com.tngtech.archunit.lang.ArchRule;

import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;

/**
 * Verifica los limites de la arquitectura hexagonal.
 *
 * <p>Estas reglas fijan el contrato estructural del proyecto antes de que
 * exista logica de negocio. Con {@code allowEmptyShould(true)} no fallan
 * mientras los paquetes esten vacios (Semana 1), pero se activan en cuanto se
 * agreguen clases en las issues posteriores.
 */
@AnalyzeClasses(
        packages = "com.centinela",
        importOptions = ImportOption.DoNotIncludeTests.class)
class ArchitectureConventionsTest {

    @ArchTest
    static final ArchRule el_dominio_no_depende_de_application =
            noClasses()
                    .that().resideInAPackage("..domain..")
                    .should().dependOnClassesThat().resideInAnyPackage("..application..")
                    .allowEmptyShould(true);

    @ArchTest
    static final ArchRule el_dominio_no_depende_de_infrastructure =
            noClasses()
                    .that().resideInAPackage("..domain..")
                    .should().dependOnClassesThat().resideInAnyPackage("..infrastructure..")
                    .allowEmptyShould(true);

    @ArchTest
    static final ArchRule application_no_depende_de_infrastructure =
            noClasses()
                    .that().resideInAPackage("..application..")
                    .should().dependOnClassesThat().resideInAnyPackage("..infrastructure..")
                    .allowEmptyShould(true);

    @ArchTest
    static final ArchRule dominio_y_application_no_usan_spring_web =
            noClasses()
                    .that().resideInAnyPackage("..domain..", "..application..")
                    .should().dependOnClassesThat().resideInAnyPackage("org.springframework.web..")
                    .allowEmptyShould(true);

    @ArchTest
    static final ArchRule dominio_y_application_no_usan_sdk_azure =
            noClasses()
                    .that().resideInAnyPackage("..domain..", "..application..")
                    .should().dependOnClassesThat().resideInAnyPackage("com.azure..")
                    .allowEmptyShould(true);
}
