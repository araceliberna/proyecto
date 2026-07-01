# Guía paso a paso: crear las bases y configurar las acciones en Power Platform

Complementa `docs/arquitectura-sistema-unificado.md`. Aquí está el "cómo hacer clic"
en el portal, en el orden en que conviene construirlo.

## Paso 0 — Environment

1. Entra a **admin.powerplatform.microsoft.com** → Environments → **+ New**.
2. Crea un Environment de **Pruebas** (tipo Sandbox) con Dataverse habilitado
   ("Add Dataverse: Yes"). Repite luego para **Producción** cuando esté probado.
3. En **Power Platform Admin Center → Data policies (DLP)**, revisa que el
   conector de SAP/RPA quede en un grupo separado de conectores no aprobados
   (ver sección 6 del documento de arquitectura).

## Paso 1 — Crear las tablas (bases) en Dataverse

Entra a **make.powerapps.com** → selecciona el Environment de Pruebas →
menú izquierdo **Tables** → **+ New table**.

Crea, una por una, las tablas del documento de arquitectura. Para cada una:
1. `+ New table` → nombre (ej. `Solpeds OC Spot`) → Save (esto crea el
   nombre lógico `cr123_solpedsocspot` automáticamente, no lo cambies).
2. Dentro de la tabla → pestaña **Columns** → `+ New column` por cada campo
   de la tabla. Usa el tipo indicado en el documento:
   - `Texto` → Data type "Text"
   - `Número` → "Whole Number" o "Decimal Number" según el campo
   - `Choice` → "Choice", y ahí defines las opciones exactas (ej. `Registrado`,
     `Convertido a OC`, `En seguimiento CoE`, `Cerrado`)
   - `Fecha` / `Fecha/hora` → "Date Only" o "Date and Time"
   - `Persona` → "Lookup" a la tabla `User` (o `Azure AD Object`, según el
     conector) — esto te da el selector de gente de tu organización.
3. Repite para las 6 tablas: `Solpeds_OC_Spot`, `EjecucionesScript`,
   `Reportes`, `QuiebresSS`, `ContratosSaldo`, `ErroresME59N`.

**Orden recomendado:** primero `Solpeds_OC_Spot` (la usarás enseguida en el
formulario), luego `QuiebresSS` y `ContratosSaldo` (alimentan el Radar de
Riesgos), después `ErroresME59N`, y al final `EjecucionesScript` y `Reportes`.

**Permisos por fila:** en cada tabla, pestaña **Settings → Security roles**,
crea o edita los roles `Planeamiento` y `CoE Compras` con los permisos
(Create/Read/Write) que correspondan según la sección 6 del documento.

## Paso 2 — Crear la Canvas App

1. `make.powerapps.com` → **Apps** → **+ New app → Canvas** → "Blank app"
   (formato Tablet, ya que será uso de escritorio).
2. Estructura de pantallas (una por cada botón del sidebar de la simulación
   que ya viste): `Inicio`, `RegistrarSolped`, `ME59N`, `Radar`, `Stockflow`,
   `ContratosISA`, `ConsultarEstado`.
3. En la pantalla `Inicio`, inserta un contenedor vertical a la izquierda
   (el "sidebar") con un botón por pantalla. En cada botón, propiedad
   `OnSelect`: `Navigate(RegistrarSolped, ScreenTransition.Fade)` (y así
   para cada pantalla).
4. Conecta los orígenes de datos: menú **Data** (panel izquierdo) → **+ Add
   data** → busca y agrega cada tabla de Dataverse creada en el Paso 1.
5. En cada pantalla, usa una **Gallery** conectada a la tabla correspondiente
   (`QuiebresSS` en Radar/Stockflow, `Solpeds_OC_Spot` en ConsultarEstado,
   etc.) para mostrar los datos, tal como en la simulación HTML.

## Paso 3 — Configurar las acciones (Power Automate) detrás de cada botón

Aquí es donde el botón deja de ser solo "navegar" y realmente **hace algo**.
La conexión Power Apps → Power Automate se hace desde el propio botón:
seleccionas el botón → pestaña **Action → Power Automate** → **+ Add flow**
(o creas el flow primero en Power Automate y luego lo enlazas ahí).

### 3.1 Botón "Guardar" en RegistrarSolped
- **Opción simple (sin flow):** en el botón, `OnSelect`:
  `Patch(Solpeds_OC_Spot, Defaults(Solpeds_OC_Spot), {NumeroSolped: TxtSolped.Text, ...})`
  — esto ya crea la fila directo en Dataverse.
- **Notificación automática:** crea un flow en Power Automate (no en la app):
  1. `make.powerautomate.com` → **+ Create → Automated cloud flow**.
  2. Trigger: **"When a row is added, modified or deleted"** (conector
     Dataverse) → tabla `Solpeds_OC_Spot`, escala "Added".
  3. Acción: **Post message in a chat or channel** (Teams) o **Send an
     email (V2)** (Outlook), con los campos de la fila (`NumeroSolped`,
     `Material`, etc.) y un link al registro.
  4. Guarda el flow. No necesita conectarse manualmente al botón: se
     dispara solo cuando `Patch` crea la fila.

### 3.2 Botón "Actualizar quiebres de SS" / "Actualizar saldo de contratos"
Estos sí requieren **Power Automate Desktop** porque hablan con SAP GUI:
1. Abre **Power Automate** (app de escritorio) → **+ New flow** →
   "Actualizar QuiebresSS".
2. Reutiliza ahí la lógica de tu script GUI Scripting actual: usa las
   acciones "SAP" del catálogo de Power Automate Desktop (Launch/attach
   SAP session, Run transaction, Export table to Excel/variable) para
   correr las consultas que hoy alimentan `SP`, `OC`, `ME2N`, `MB52`, etc.
3. Agrega un bloque que arme el cruce (igual que la hoja `BD`) y calcule
   `StatusStock` (`Quiebre` si `StockActual < StockSeguridad`).
4. Al final, usa la acción **"Invoke Dataverse action"** o el conector
   Dataverse para hacer upsert en la tabla `QuiebresSS` (una fila por
   `CentroMaterial`).
5. Guarda el flow de escritorio. Luego, en **Power Automate (cloud)**, crea
   un flow "padre":
   - Trigger: **"Power Apps (V2)"** (para que el botón lo dispare) — o
     **Recurrence** si prefieres que corra solo, ej. cada mañana.
   - Acción: **"Run a flow built with Power Automate for desktop"**,
     seleccionando el flow de escritorio del paso anterior. Esto requiere
     una máquina con **Power Automate Desktop gateway** instalada y el SAP
     GUI configurado (tu PC, o una VM dedicada).
6. En Power Apps, en el botón "Actualizar quiebres de SS": pestaña
   **Action → Power Automate**, selecciona este flow "padre" y en
   `OnSelect` agrégalo con `NombreDelFlow.Run()`.

### 3.3 Botón "Generar Solped automáticas (ME59N)"
Mismo patrón que 3.2, pero el flow de escritorio:
1. Abre `ME59N` en SAP GUI (acción "SAP – Run transaction").
2. Filtra por UN (parámetro que le pasas al flow desde Power Apps: `UN1`
   o `UN2`) y ejecuta la conversión masiva.
3. Exporta el log de aplicación resultante (columna de mensajes) a una
   tabla/lista dentro del flow.
4. Con un bloque **"Switch"** o reglas `If/Contains`, clasifica cada
   mensaje de error por palabras clave (`"bloqueado"` → `Proveedor
   bloqueado`, `"fuente de suministro"` → `Sin fuente de suministro`, etc.)
   y arma una lista de errores.
5. Sube los éxitos como actualización de `Solpeds_OC_Spot.Estado =
   "Convertido a OC"` y los errores como filas nuevas en `ErroresME59N`
   (con acción Dataverse "Add a new row", en bucle "For each").
6. En el flow cloud "padre", usa **"Run a flow built with Power Automate
   for desktop"** pasándole el parámetro `UN` que venga del botón en
   Power Apps: `MEsub59NFlow.Run(Radio_UN.Selected.Value)`.
7. Al terminar, agrega una acción de notificación condicional (`If
   Categoria = "Proveedor bloqueado"` → Teams a Compras/Finanzas; `If
   Categoria = "Dato maestro"` → Teams al Planeador; etc.), usando un
   **Apply to each** sobre las filas nuevas de `ErroresME59N`.

### 3.4 Botón "Generar reporte"
1. Flow cloud con trigger **Power Apps (V2)**.
2. Acción "Run a flow built with Power Automate for desktop" (si necesita
   datos frescos de SAP) o directo si solo compone con lo que ya hay en
   Dataverse/Calendar.
3. Acción **"Populate a Microsoft Word/Excel template"** (conector
   "Word Online (Business)" o "Excel Online (Business)") usando una
   plantilla guardada en SharePoint.
4. Guarda el archivo resultante en una biblioteca de SharePoint (acción
   "Create file").
5. Agrega una fila en `Reportes` con el link generado.
6. Notifica (Teams/correo) con el enlace.

### 3.5 Botón "Enviar notificación" (genérico)
- Flow cloud simple: trigger **Power Apps (V2)** con un parámetro de texto
  (el mensaje) → acción **Post message in a chat or channel** o **Send an
  email (V2)**. Este es el más simple de todos, buen punto de partida para
  practicar el patrón Power Apps → Power Automate antes de ir a los flows
  más complejos de SAP.

## Paso 4 — Probar antes de automatizar todo

Orden sugerido para no atascarte:
1. Primero deja funcionando **RegistrarSolped** (Paso 3.1) — no depende de
   SAP, solo de Dataverse + Teams/correo. Es el más rápido de validar.
2. Luego **"Enviar notificación"** genérico (3.5) para practicar el patrón
   Power Apps → Power Automate con trigger manual.
3. Recién después monta los flows de escritorio que hablan con SAP (3.2 y
   3.3) — son los que más tiempo toman porque dependen de tener Power
   Automate Desktop instalado, con sesión de SAP GUI accesible desde la
   máquina donde corre el flow.

## Qué necesitas tener antes de empezar

- Acceso a `make.powerapps.com` con licencia de Power Apps (per-app o
  per-user) y Dataverse habilitado en el Environment.
- Licencia de Power Automate con complemento de **RPA / Process Mining**
  (o "Power Automate per user with attended RPA plan") para los flows de
  escritorio que tocan SAP.
- Power Automate Desktop instalado en la máquina que ejecutará los flows
  de SAP (tu PC de trabajo, con SAP GUI ya configurado, o una VM dedicada
  si se quiere que corra sin tu sesión abierta — requiere licencia
  "unattended").
