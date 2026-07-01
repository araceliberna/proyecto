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

Y disparar, con botones, estos tipos de acción:
1. Registrar un formulario (Solped → OC Spot) que el CoE de Compras da seguimiento.
2. Generar reportes/resúmenes.
3. Enviar notificaciones.
4. Ejecutar tareas/scripts (incl. los de SAP).
5. Generar Solped automáticas a OC por UN (`ME59N`), clasificando y
   notificando los errores que SAP arroje.
6. Consultar estado de lo anterior (incl. Radar de Riesgos).

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

## 3.1 Fuente concreta: Reporte SS (quiebres de stock de seguridad)

Hoy este reporte es un Excel semanal con macros (`Reporte SS Semana N-2026.xlsm`,
~55 MB) que se arma a mano cruzando varias extracciones de SAP. Su estructura,
que sirve de base para automatizarlo:

- Hoja **`BD`**: tabla maestra (77 columnas, ~75,000 filas), clave `C&M`
  (Centro + Material), que cruza:
  - `SP` (Solicitudes de pedido / Solpeds)
  - `OC` (Órdenes de compra)
  - `ME2N` (seguimiento de pedidos SAP)
  - `Stock en piso` (extracción tipo MB52)
  - `Consumos`, `Consumo Histórico`, `Ingresos`, `Reservas`, `Contratos`
- Columna clave **`Status sobrestock`**: `En stock` / `Quiebre` / `Sobre Stock`.
  Regla: `Quiebre` cuando `Stock actual < Stock de seguridad` (columna `Dif`
  negativa).
- Columna **`Status Consumo`**: `Óptimo` / `Baja rotación` / `Inmovilizado` /
  `Sin consumo histórico` — complementa el diagnóstico de cada material.
- Hoja **`Resultados`**: resumen tipo pivot con el % de `Quiebre` / `En stock`
  / `Sobre Stock` por tipo de material (ZERS, ZHIB), filtrado por Sociedad,
  Contrato y Grupo de compras.

**Por qué no conviene que el botón "actualice el Excel":** el archivo pesa
~55 MB, tiene macros, y depende de refrescar manualmente varias consultas SAP
distintas cada semana. En vez de eso, el botón debe disparar la actualización
de una tabla en Dataverse:

**Tabla `QuiebresSS`** (equivalente a la hoja `BD`, sólo los campos que
alimentan la alerta y el filtro)
| Campo | Tipo | Notas |
|---|---|---|
| ID | Autonumérico | |
| CentroMaterial | Texto | Clave `C&M` (Centro + Material) |
| Centro | Texto | |
| Material | Texto | |
| TextoBreve | Texto | Descripción del material |
| TipoMaterial | Choice | `ZERS` / `ZHIB` / `ZNLA` |
| StockSeguridad | Número | |
| StockActual | Número | |
| Diferencia | Número | `StockActual - StockSeguridad` |
| StatusStock | Choice | `En stock` / `Quiebre` / `Sobre Stock` |
| StatusConsumo | Choice | `Óptimo` / `Baja rotación` / `Inmovilizado` / `Sin consumo histórico` |
| Proveedor | Texto | |
| FechaEntregaOC | Fecha | Si hay OC abierta relacionada |
| FechaReporte | Fecha/hora | Última actualización (reemplaza el refresh manual semanal) |

**Flujo propuesto para el botón "Actualizar quiebres de SS":**
1. Power Automate Desktop ejecuta las mismas consultas SAP que hoy alimentan
   `SP`, `OC`, `ME2N`, `MB52`, Consumos, Ingresos, Reservas y Contratos
   (reusando/parametrizando los scripts GUI Scripting existentes).
2. Un paso de transformación reproduce el cruce que hoy hace la hoja `BD`
   (join por Centro+Material) y calcula `StatusStock` con la misma regla
   (`StockActual < StockSeguridad` → `Quiebre`).
3. Se hace un *upsert* a la tabla `QuiebresSS` en Dataverse (reemplaza filas
   por `CentroMaterial`, no re-crea todo).
4. La pantalla "Consultar estado" / Radar de Riesgos lee `QuiebresSS`
   directamente — sin abrir el Excel, y con historial de cuándo fue la
   última actualización.
5. Opcional: seguir generando el Excel semanal como archivo de respaldo
   (guardado en SharePoint), pero ya no como fuente en vivo del dashboard.

## 3.2 Fuente concreta: Reporte de Contratos (saldo y ampliación)

Mismo patrón que el Reporte SS: un Excel semanal pesado (`CONTRATOS_SEM_N.xlsb`,
~60 MB) que cruza varias extracciones SAP en una hoja maestra.

- Hoja **`TOTAL CONTRATOS`**: tabla maestra (61 columnas, clave `C&M` =
  Centro+Material), que cruza:
  - `ME3M` (posiciones de contrato marco en SAP: cantidades, valores, proveedor)
  - `Consumo` (consumo real acumulado por material)
  - `MB51` (movimientos de material, para trazar consumo/salidas)
  - `ME5A` (solicitudes de pedido pendientes contra el contrato)
- Columnas clave: `Cantidad Total`, `Cantidad Pendiente`, `SALDO CANTIDAD`,
  `Consumo mensual`, `Consumo proyectado hasta final del contrato`,
  `Saldo valorizado`, `Fecha Inicio`/`Fecha Fin`, `Días en contrato`.
- Columna **`Por ampliar`**: `No` / `Sí` / `Revisión por el COE`. Se marca
  `Sí` cuando `SALDO CANTIDAD < 0` (el consumo proyectado hasta el fin del
  contrato supera lo que queda pendiente/disponible), y trae ya calculado
  `Cantidad a ampliar` y `Valorizado a ampliar` — el insumo directo para la
  alerta "📊 Saldo Contrato Bajo" del Radar de Riesgos.

**Tabla `ContratosSaldo`** (Dataverse, equivalente resumido de `TOTAL CONTRATOS`)
| Campo | Tipo | Notas |
|---|---|---|
| ID | Autonumérico | |
| CentroMaterial | Texto | Clave `C&M` |
| Contrato | Texto | Nº de contrato marco |
| Posicion | Texto | `POS` |
| Proveedor | Texto | |
| CantidadTotal | Número | |
| CantidadPendiente | Número | |
| SaldoCantidad | Número | |
| ConsumoMensual | Número | |
| ConsumoProyectado | Número | Hasta fin de contrato |
| SaldoValorizado | Número | |
| PorAmpliar | Choice | `No` / `Sí` / `Revisión por el COE` |
| CantidadAAmpliar | Número | |
| ValorizadoAAmpliar | Número | |
| FechaFinContrato | Fecha | |
| FechaReporte | Fecha/hora | Última actualización |

**Flujo del botón "Actualizar saldo de contratos"**: igual patrón que
`QuiebresSS` — Power Automate Desktop corre las consultas SAP detrás de
`ME3M`, `Consumo`, `MB51` y `ME5A`, reproduce el cruce y el cálculo de
`PorAmpliar`, y hace upsert en `ContratosSaldo`. Con `PorAmpliar = Sí`, el
botón de acción en el Radar de Riesgos puede ser directamente "Solicitar
ampliación" (dispara notificación al Comprador/CoE con los datos ya
calculados: cuánto ampliar y su valorización).

## 3.3 Generación automática de Solped → OC (ME59N) y manejo de errores

Para UN1/UN2 (u otras unidades de negocio que definas), la idea es que un
botón dispare la conversión masiva de Solpeds a OC directamente en SAP
(transacción `ME59N`), en vez de convertirlas una por una manualmente.

**Cómo funciona `ME59N` y por qué falla:** SAP intenta generar el pedido
para cada Solped seleccionada; si falta un dato (fuente de suministro no
fijada, proveedor bloqueado, falta registro de información de compras,
diferencia de unidad de medida, etc.) SAP no la convierte y deja un mensaje
de error en el log de aplicación de esa ejecución (el mismo log que hoy ves
en pantalla al correr la transacción).

**Flujo propuesto para el botón "Generar Solped automáticas (ME59N)":**
1. Power Automate Desktop abre `ME59N`, filtra por UN (UN1/UN2) y por los
   criterios que definas (p. ej. Solpeds liberadas, sin bloqueo, con fuente
   de suministro asignada) y ejecuta la conversión masiva.
2. El flujo lee el log de aplicación que arroja SAP al terminar (éxitos y
   errores por Solped/posición).
3. Los éxitos actualizan el estado en `Solpeds_OC_Spot` a `Convertido a OC`
   con el número de OC generado.
4. Los errores se guardan en una tabla `ErroresME59N` (ver modelo de datos)
   y se **clasifican automáticamente** por palabras clave del mensaje SAP
   (p. ej. "proveedor bloqueado", "sin fuente de suministro", "diferencia de
   UM") en una categoría conocida.
5. Según la categoría, el flujo notifica a quien corresponde: proveedor
   bloqueado → Compras/Finanzas; sin fuente de suministro o dato maestro →
   Planeador; el resto → categoría "Otro" para revisión manual.
6. Estos errores también alimentan el Radar de Riesgos como una alerta más
   ("Solped sin convertir") junto a las 4-5 ya definidas.

**Tabla `ErroresME59N`**
| Campo | Tipo | Notas |
|---|---|---|
| ID | Autonumérico | |
| NumeroSolped | Texto | |
| Posicion | Texto | |
| Material | Texto | |
| UnidadNegocio | Choice | `UN1` / `UN2` / otras |
| MensajeSAP | Texto largo | Mensaje de error tal cual lo entrega SAP |
| Categoria | Choice | `Proveedor bloqueado` / `Sin fuente de suministro` / `Dato maestro` / `Diferencia UM` / `Otro` |
| Estado | Choice | `Pendiente` / `Resuelto` |
| ResponsableNotificado | Persona | Según la categoría |
| FechaEjecucion | Fecha/hora | |

*Nota:* la clasificación por palabras clave es un punto de partida; conviene
revisar contigo el listado real de mensajes de error que arroja `ME59N` en
tu operación para afinar las categorías y evitar que caigan todos en "Otro".

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

### 5.5 "Generar Solped automáticas (ME59N)"
- Botón por UN (UN1/UN2) que dispara el flujo descrito en la sección 3.3:
  corre `ME59N` para las Solpeds candidatas de esa unidad de negocio.
- Muestra al terminar un resumen: cuántas se convirtieron a OC y cuántas
  quedaron en error, con enlace directo a la pantalla de estado para ver
  el detalle clasificado de los errores (`ErroresME59N`).
- Los errores no se pierden en el log de SAP: quedan clasificados y
  notificados a quien debe resolverlos (Compras/Finanzas si es proveedor
  bloqueado, Planeador si es un dato maestro faltante, etc.).

### 5.6 "Consultar estado"
- Pantalla con 4 galerías: Solpeds (con su estado y quién las creó),
  últimas ejecuciones de scripts (éxito/error), reportes generados, y
  **Radar de Riesgos** (quiebres de SS desde `QuiebresSS`, más las otras
  alertas del mockup: saldo de contrato bajo, proveedor bloqueado, entrega
  en riesgo, presupuesto en riesgo — ver `docs/mockups/radar-riesgos.html`).
- Filtros por fecha, estado, solicitante, tipo de material (ZERS/ZHIB/ZNLA)
  y urgencia.
- Un botón "Actualizar quiebres de SS" dispara el flujo descrito en la
  sección 3.1 y refresca `QuiebresSS` bajo demanda (además de poder
  programarse automáticamente, p. ej. cada mañana).

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
