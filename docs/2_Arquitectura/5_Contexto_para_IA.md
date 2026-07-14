# 00 — Contexto backend para IA

## Proyecto

Centinela es un motor de detección de fraude transaccional en tiempo real sobre Azure. Este documento solo autoriza trabajo de Semana 1.

## Objetivo de Semana 1

Construir los cimientos para que una transacción pueda entrar, validarse y almacenarse sin ejecutar análisis. También deben quedar operativas la carga técnica de documentos y una cola de ingesta validada.

## Alcance obligatorio

- Infraestructura reproducible con Bash y Azure CLI.
- Entra ID, roles y mínimo privilegio.
- Red privada y Storage no accesible desde Internet.
- App Service con `staging` separado.
- Alta disponibilidad demostrable.
- API REST en Java 21 y Spring Boot.
- Persistencia cruda en Blob Storage.
- Carga de documentos en Blob Storage.
- Queue Storage creada y validada.
- Documentación y evidencias.

## Fuera de alcance

- Reglas de fraude, scoring y umbral.
- Consumidor de cola.
- Casos de fraude.
- Bases de datos de Semana 2.
- IA.
- Automatización completa de despliegue.
- GitHub Actions obligatorio.

## Restricción económica

El equipo tiene cinco integrantes y un crédito total de USD 200. Se usa un solo entorno integrado y se destruye cuando no sea necesario.

## Regla para futuras semanas

No inventar decisiones de Semana 2. Semana 1 solo debe dejar contratos y puertos que permitan conectar el motor posterior.
