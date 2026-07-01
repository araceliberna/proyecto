# Sistema Unificado de Trabajo — Planeamiento de Materiales Indirectos

Documento de arquitectura y guía de implementación para una app de Power Platform
que centralice información y ejecute acciones (botones) para el área de
Planeamiento de Materiales Indirectos: conversión de Solped a OC Spot,
reportes, notificaciones, ejecución de tareas SAP y consulta de estado.

## 1. Objetivo

Unificar en un solo panel:
- Datos de SAP (vía scripts existentes, GUI Scripting/VBS y reportes exportados).
- Calendario y correo (Google Calendar / Outlook).
- Documentos locales (reportes, plantillas).
- Un formulario para que otra persona registre requerimientos de Solped → OC Spot.

Y disparar, con botones, cuatro tipos de acción:
1. Registrar un formulario (Solped → OC Spot) que el CoE de Compras da seguimiento.
2. Generar reportes/resúmenes.
3. Enviar notificaciones.
4. Ejecutar tareas/scripts (incl. los de SAP).
5. Consultar estado de lo anterior.

## 2. Por qué Power Platform

- Se apoya en tu Azure AD corporativo: permisos por rol sin gestionar usuarios aparte.
- Dataverse/SharePoint dan una base de datos versionada y con permisos a nivel de fila.
- Power Automate Desktop permite reutilizar tus scripts de SAP (GUI Scripting) como
  un flujo controlado y auditable, en vez de macros sueltas en tu PC.
- Power Apps Canvas da la interfaz de "botones" pedida, sin necesitar desarrollo web.

## 3. Componentes

| Componente | Rol |
|---|---|
| **Power Apps (Canvas App)** | Interfaz con botones y el formulario de Solped → OC Spot. |
| **Dataverse** (o SharePoint Lists si no hay licencia Dataverse) | Almacena solicitudes, estados, historial de reportes. |
| **Power Automate (Cloud Flows)** | Orquesta: guarda datos, envía notificaciones, dispara generación de reportes, consulta estado. |
| **Power Automate Desktop (RPA)** | Ejecuta tus scripts SAP GUI Scripting existentes de forma controlada, devuelve resultado al flujo cloud. |
| **Conector Outlook/Google Calendar** | Trae reuniones/plazos relevantes a la pantalla de estado. |
| **SharePoint (biblioteca de documentos)** | Repositorio de los reportes generados y documentos locales que hoy tienes sueltos. |
| **Teams/Outlook (notificaciones)** | Canal de aviso al CoE de Compras y a ti mismo. |

Diagrama de flujo (alto nivel):

```
[Power Apps: botones] 
      │
      ├─► Nuevo requerimiento Solped→OC Spot ─► Dataverse (tabla Solpeds)
      │         └─► Power Automate: notifica a CoE Compras (Teams/correo)
      │
      ├─► Generar reporte ─► Power Automate
      │         ├─► Power Automate Desktop: corre script SAP (extrae datos)
      │         ├─► Lee Calendar/Outlook (contexto de plazos)
      │         ├─► Compone Excel/Word desde plantilla
      │         └─► Guarda en SharePoint + notifica
      │
      ├─► Ejecutar tarea/script ─► Power Automate Desktop (tu VBS/GUI Scripting)
      │
      ├─► Enviar notificación ─► Power Automate (Teams/Outlook)
      │
      └─► Consultar estado ─► Galería en Power Apps leyendo Dataverse
                (estado de cada Solped/OC, últimas ejecuciones de scripts, reportes generados)
```

## 4. Modelo de datos (Dataverse / SharePoint)

**Tabla `Solpeds_OC_Spot`**
| Campo | Tipo | Notas |
|---|---|---|
| ID | Autonumérico | |
| NumeroSolped | Texto | |
| Material | Texto | |
| Cantidad | Número | |
| CentroCosto | Texto | |
| SolicitadoPor | Persona (lookup a Azure AD) | Quien llena el formulario |
| Estado | Choice | `Registrado` / `Convertido a OC` / `En seguimiento CoE` / `Cerrado` |
| NumeroOCSpot | Texto | Se llena cuando el CoE convierte |
| FechaRegistro | Fecha | |
| Comentarios | Texto largo | |

**Tabla `EjecucionesScript`**
| Campo | Tipo | Notas |
|---|---|---|
| ID | Autonumérico | |
| TipoScript | Choice | `GUI Scripting` / `Reporte exportado` |
| EstadoEjecucion | Choice | `Pendiente` / `En curso` / `Exitoso` / `Error` |
| FechaEjecucion | Fecha/hora | |
| LogResultado | Texto largo | Salida o error del script |

**Tabla `Reportes`**
| Campo | Tipo | Notas |
|---|---|---|
| ID | Autonumérico | |
| Nombre | Texto | |
| FechaGeneracion | Fecha/hora | |
| EnlaceSharePoint | Texto (URL) | |
| GeneradoPor | Persona | |

## 5. Detalle de cada botón

### 5.1 "Registrar requerimiento Solped → OC Spot"
- Formulario en Power Apps con los campos de la tabla `Solpeds_OC_Spot`.
- Al guardar: Power Automate crea el registro y envía notificación (Teams/correo)
  al buzón/canal del CoE de Compras con los datos clave y un enlace directo al
  registro para que solo den seguimiento (sin duplicar captura de datos).
- Quien llena el formulario puede ser tú u otra persona de tu área con acceso
  a esa pantalla (rol "Solicitante").

### 5.2 "Generar reporte"
- Dispara un flujo que:
  1. Llama a Power Automate Desktop para correr el script SAP y traer datos frescos.
  2. Combina con datos de Dataverse (estado de Solpeds/OC) y Calendar (plazos).
  3. Llena una plantilla Excel/Word ya definida.
  4. Guarda el archivo en SharePoint y registra la fila en `Reportes`.
  5. Notifica con el enlace al reporte.

### 5.3 "Enviar notificación"
- Botón genérico que dispara un flujo de Power Automate para avisar por Teams
  o correo (por ejemplo, recordatorio al CoE de Compras sobre Solpeds pendientes
  hace X días, usando un flujo programado adicional si se quiere automático).

### 5.4 "Ejecutar tarea/script"
- Botón que dispara el flujo de Power Automate Desktop correspondiente a tu
  script SAP GUI Scripting. El resultado (éxito/error, log) se guarda en
  `EjecucionesScript` y se refleja en la pantalla de estado.
- Los reportes que hoy exportas manualmente de SAP se documentan como el
  mismo tipo de acción, para dejar rastro de cuándo y quién los generó.

### 5.5 "Consultar estado"
- Pantalla con 3 galerías: Solpeds (con su estado y quién las creó),
  últimas ejecuciones de scripts (éxito/error), y reportes generados.
- Filtros por fecha, estado y solicitante.

## 6. Seguridad y accesos (tu preocupación principal)

- **Roles en Power Apps**: define al menos dos roles vía Azure AD Security
  Groups — `Planeamiento` (crea Solpeds, ejecuta scripts, genera reportes) y
  `CoE Compras` (solo ve y actualiza estado/OC de las Solpeds asignadas).
- **DLP policies** en el Environment de Power Platform: restringe qué conectores
  pueden combinarse (evita que el conector SAP/RPA se mezcle con conectores
  no aprobados, p. ej. redes sociales).
- **Credenciales SAP**: usa un usuario de servicio con permisos mínimos
  (solo las transacciones que el script necesita) en vez de tu usuario personal;
  las credenciales se guardan cifradas en Power Automate Desktop (Azure Key
  Vault o el gestor de credenciales de Power Platform), nunca en texto plano
  en el flujo.
- **Auditoría**: Dataverse guarda automáticamente quién y cuándo modifica cada
  registro; actívalo también en el Environment para tener trazabilidad de las
  ejecuciones de script.
- **Ambiente separado**: crea un Environment de "Desarrollo/Pruebas" distinto
  al de "Producción" para no arriesgar el acceso real a SAP mientras pruebas.

## 7. Guía de implementación por fases

**Fase 0 — Preparación**
- Confirmar licenciamiento (Power Apps per-user o per-app, Power Automate
  con complemento de RPA para Desktop, y si hay Dataverse disponible).
- Crear el Environment dedicado y los Security Groups (`Planeamiento`, `CoE Compras`).

**Fase 1 — MVP (1–2 semanas)**
1. Crear tabla `Solpeds_OC_Spot` en Dataverse (o lista de SharePoint si no hay Dataverse).
2. Construir la Canvas App con: pantalla de inicio (botones), formulario de
   registro, y galería de consulta de estado.
3. Flujo de Power Automate: al guardar formulario → notificación a CoE Compras.

**Fase 2 — Integración SAP**
1. Empaquetar el script GUI Scripting existente como un flujo de Power
   Automate Desktop, parametrizado (que reciba inputs y devuelva outputs/log).
2. Conectar el botón "Ejecutar tarea/script" a ese flujo.
3. Registrar resultado en tabla `EjecucionesScript`.

**Fase 3 — Reportes y notificaciones enriquecidas**
1. Definir la(s) plantilla(s) de reporte.
2. Flujo que combina SAP + Dataverse + Calendar y genera el archivo en SharePoint.
3. Botón de notificación general y, si se desea, recordatorios automáticos
   programados (Solpeds pendientes hace N días).

**Fase 4 — Roles y auditoría**
1. Afinar permisos por Security Group.
2. Activar auditoría en Dataverse.
3. Revisar DLP policies del Environment.

## 8. Qué falta definir contigo antes de construir en el portal

- Nombre exacto de las transacciones SAP que corre el script (para
  parametrizar el flujo de Power Automate Desktop).
- Plantilla(s) de reporte actuales (formato Excel/Word) para replicarlas.
- Canal de notificación preferido del CoE de Compras (Teams, correo, ambos).
- Si ya cuentan con licencia Dataverse o se debe usar SharePoint Lists como
  alternativa gratuita.
