# Flujos de Power Automate (especificación acción por acción)

Power Automate no se escribe como texto plano — se arma en el diseñador
visual — pero aquí tienes cada flow ya descompuesto en la secuencia exacta
de acciones para que solo las vayas agregando en orden, sin tener que
decidir el diseño sobre la marcha. Los nombres en **negrita** son literales:
así se buscan en el catálogo de acciones del diseñador.

---

## Flow 1 — "Notificar nueva Solped" (cloud, automático)

**Tipo:** Automated cloud flow
**Trigger:** **When a row is added, modified or deleted** (conector
Microsoft Dataverse)
- Table: `Solpeds_OC_Spot`
- Scope: `Organization`
- Filtering: dejar la trigger condition en el paso de "Added" únicamente
  (o usar el campo `Estado` y filtrar por `Registrado`).

**Acciones:**
1. **Condition**: `Estado` (del disparador) es igual a `Registrado`
   - Si es verdadero:
2. **Post message in a chat or channel** (Teams) *o* **Send an email (V2)**
   (Outlook) — destinatario: canal/correo del CoE de Compras.
   - Cuerpo sugerido:
     ```
     Nueva Solped registrada: {NumeroSolped}
     Material: {Material}
     Cantidad: {Cantidad}
     Centro de costo: {CentroCosto}
     Registrado por: {SolicitadoPor.FullName}
     Comentarios: {Comentarios}
     Ver registro: {enlace directo al registro en la app}
     ```

No requiere trigger desde Power Apps: se dispara solo al hacer `Patch`.

---

## Flow 2 — "Ejecutar ME59N" (cloud, invocado desde el botón)

**Tipo:** Automated cloud flow
**Trigger:** **Power Apps (V2)**
- Parámetro de entrada: `UnidadNegocio` (texto, valores esperados `UN1`/`UN2`)

**Acciones:**
1. **Run a flow built with Power Automate for desktop** → selecciona el
   flow de escritorio `ME59N - Conversion Masiva` (ver Flow 2b abajo),
   pasando `UnidadNegocio` como parámetro de entrada.
2. El flow de escritorio devuelve dos variables de salida: `ListaExitos`
   (tabla) y `ListaErrores` (tabla, con columnas `PedidoAbierto`,
   `PosPedidoAbierto`, `Solped`, `PosSolped`, `Material`, `MensajeSAP`,
   `ClaseMensaje`, `NumeroMensaje`) — confirmado con el log real de SAP:
   solo se cuentan como error las filas con **ícono 🔴 (rojo)**; las 🔺
   (naranja/triángulo) son advertencias informativas que no bloquean la
   conversión y se descartan al armar `ListaErrores`.
3. **Apply to each** sobre `ListaExitos`:
   - **Update a row** (Dataverse) en `Solpeds_OC_Spot` — busca por
     `NumeroSolped` igual al ítem actual, set `Estado = "Convertido a OC"`,
     `NumeroOCSpot = <ítem.OC>`.
4. **Apply to each** sobre `ListaErrores`:
   - **Switch** sobre `ClaseMensaje` + `NumeroMensaje` (más confiable que
     buscar texto, porque el código de mensaje no cambia aunque cambie la
     redacción) → variable `Categoria` — ver tabla de clasificación abajo.
   - **Add a new row** (Dataverse) en `ErroresME59N` con `NumeroSolped`,
     `Posicion`, `Material`, `UnidadNegocio`, `MensajeSAP`, `Categoria`,
     `Estado = "Pendiente"`.
   - **Condition** sobre `Categoria`:
     - `"Saldo de contrato excedido"` → notificar a Comprador/CoE (mismo
       destino que las alertas de `ContratosSaldo` — es el mismo problema
       de fondo: el pedido abierto/contrato ya no tiene saldo).
     - `"Error de prueba/configuración"` u `"Otro"` → notificar al canal
       general de PMI para revisión manual (causa no identificable
       automáticamente todavía).
5. **Response** (si el trigger es Power Apps V2, usa la acción
   **"Respond to a PowerApp or flow"**) con dos salidas numéricas:
   `convertidas = length(ListaExitos)`, `errores = length(ListaErrores)`.
   Esto es lo que Power Apps recibe en `varResultadoME59N.convertidas` /
   `.errores` (ver `docs/codigo/powerfx-formulas.md`, sección 3).

### Tabla de clasificación de errores (bloque "Switch")

Basada en el log real de `ME59N` que compartiste. Clasifica por
**clase + número de mensaje** (más estable que el texto):

| Ícono | Clase / Nº | Mensaje | Categoría | Notificar a |
|---|---|---|---|---|
| 🔴 | `06` / `042` | "El valor previsto del pedido abierto {OC} se ha excedido en {monto} {moneda}" | Saldo de contrato excedido | Comprador / CoE Compras |
| 🔴 | (sin clase clara) | "Ejecución de test incorrecta" | Error de prueba/configuración | Canal PMI (revisión manual) |
| 🔴 | (sin clase clara) | "La solicitud de pedido no ha podido crearse" | Resultado final de fallo — **no es la causa**, es la bandera de que esa Solped/posición no se convirtió; la causa real es el mensaje 🔴 asociado en el mismo bloque del log | según la causa asociada |
| — | (cualquier otro código) | (no visto aún) | Otro | Canal PMI (revisión manual) |

Los 🔺 (naranja) que aparecieron en el mismo log (`06/207` diferencia de
precio, `06/041` contrato vencido, `MEP.../252` centro de origen
transferido, `ME/039` fecha de entrega en el pasado, `06/245` fecha
realista sugerida, `ME/589` fecha estadística en el pasado) son
**advertencias, no bloquean la conversión** — no se guardan en
`ErroresME59N`, aunque si quieres verlas igual (para revisión manual sin
que cuenten como error) se pueden guardar con `Estado = "Advertencia"` en
vez de descartarlas.

**Cómo agrupar el log por Solped:** el log de SAP es jerárquico — una fila
con los identificadores (`Pedido abierto`, `Posición`, `Solped`, `Posición
Solped`) antecede a sus mensajes asociados, hasta la siguiente fila de
identificadores. El flow debe agrupar así: cada bloque de mensajes
pertenece a la última fila de identificadores vista antes de él.

**Aún faltan ejemplos de:** proveedor bloqueado, sin fuente de suministro,
dato maestro faltante, diferencia de unidad de medida — las categorías que
había puesto como hipótesis inicial no aparecieron en este log. Si tienes
más pantallazos de corridas con esos casos, se agregan a la tabla; si
nunca ocurren en la práctica, se puede simplificar la clasificación a solo
las 2-3 categorías reales que sí aparecen.

---

## Flow 2b — "ME59N - Conversion Masiva" (Power Automate **Desktop**)

Este corre en tu PC (o VM) con SAP GUI abierto, vía Power Automate Desktop.
Se confirmó con el script real (`ME5A.txt`) y el export de ejemplo
(10,913 filas) cómo se arma hoy la lista de "Solpeds sin atender", así que
el flow queda en dos etapas: **A) generar la lista de candidatas** y
**B) correr `ME59N`** solo con esas.

### Etapa A — Generar lista de candidatas (basado en tu script ME5A actual)

1. **SAP – Launch SAP Logon and log on to SAP** (o **Attach to running
   instance**).
2. **SAP – Run transaction**: `ME5A`.
3. **SAP – Set field value** en la selección múltiple de Grupo de compras
   (`EKGRP`) = `005` (igual que tu script).
4. **SAP – Set field value** en la selección múltiple de Centro
   (`S_WERKS`), 3 líneas: `10*`, `15*`, `16*` (igual que tu script).
5. **SAP – Set field value** en `S_STATU-LOW` = `N` (estado "no tratadas",
   confirmado contigo).
6. **SAP – Run current transaction** (F8 / btn[8]).
7. **Aplicar el filtro de exclusión nativo del ALV** (esto ya lo tienes
   scripteado — se reutiliza tal cual, es más confiable que filtrar la
   tabla después en Power Automate porque usa el propio motor de filtros
   de SAP):
   - **SAP – Press button** `btn[29]` de la barra de herramientas del
     grid (ícono "Filtro").
   - Buscar el campo `Indicador de borrado` en el diálogo de criterios
     (`&FIND` con texto `"indicad"`), seleccionarlo, aplicar
     (`btnAPP_WL_SING`).
   - Abrir el popup de selección de valores del campo (`btn%_%%DYN001_%`),
     ir a la pestaña de **exclusión de valores únicos**, y excluir `true`.
   - Repetir para el segundo campo (`DYN002`, columna `Concluida`),
     excluyendo `X`.
   - Confirmar (`btn[8]` / Enter) para que el ALV quede filtrado, sin
     filas `Indicador de borrado = true` ni `Concluida = X`.
8. **Aplicar un tercer criterio de exclusión: `Contrato marco` vacío**
   (solo las Solpeds con contrato marco asignado se pueden convertir por
   este medio — confirmado contigo). Mismo diálogo de filtro (`btn[29]`),
   pero esta vez seleccionando directamente el campo `Contrato marco` (fila
   7 de la lista de criterios, según tu script) y usando la pestaña
   **"Excluir valores únicos" (`tabpNOSV`)** con el **operador "vacío" /
   "is initial"** en vez de un valor puntual:
   - Seleccionar el campo `Contrato marco` en el diálogo de criterios
     (`cntlCONTAINER1_FILT`, fila 7) y aplicarlo (`btnAPP_WL_SING`, o el
     botón `600_BUTTON` según el paso del script).
   - Abrir el popup de valores (`btn%_%%DYN001_%`) → pestaña **"Excluir
     valores únicos"** (`tabpNOSV`).
   - En vez de escribir un valor, usar el botón de patrones de selección
     (`btnRSCSEL_255-SOP_E[0,0]`) y elegir en el popup de opciones
     (`OPTION_CONTAINER`) el operador **"Vacío" / "Is Initial"** (doble
     clic sobre esa opción) — esto excluye todas las filas donde
     `Contrato marco` viene en blanco.
   - Confirmar (`btn[8]` / Enter) para aplicar.
9. **SAP – Get table from SAP screen** sobre el resultado **ya filtrado
   con los 3 criterios** (borrado, concluida, y contrato marco vacío) →
   variable `ListaFiltradaSAP`, con las mismas 32 columnas del export
   (`Solicitud de pedido`, `Centro`, `Material`, `Contrato marco`,
   `Fecha de liberación`, `Modificado el`, etc.) — ya no hace falta ningún
   paso de "Filter data table" en Power Automate para los 3 primeros
   criterios, porque quedan 100% automáticos dentro de SAP.

10. **Cuarto criterio — máximo 3 días desde su generación (este si se
    calcula en Power Automate, no en el ALV):** hoy este paso lo haces a
    mano, mirando cuál de los dos campos `Fecha de liberación` /
    `Modificado el` es más reciente. Se automatiza con un **For each**
    sobre `ListaFiltradaSAP`:
    - **Set variable** `FechaReferencia` = la mayor entre
      `CurrentItem['Fecha de liberación']` y `CurrentItem['Modificado
      el']` (acción **"If"**/comparación de fechas, o expresión
      `if(FechaLiberacion > ModificadoEl, FechaLiberacion, ModificadoEl)`).
    - **Set variable** `DiasTranscurridos` = diferencia en días entre
      `Fecha actual` y `FechaReferencia` (acción **"Subtract dates"**).
    - **If** `DiasTranscurridos <= 3`: **Add item to list**
      `ListaCandidatas` (agrega la fila); si no, se descarta (sigue
      "vigente hasta el 3er día", tal como confirmaste — al 4to día ya no
      entra).
11. **Add a new row** (Dataverse, opcional) en `EjecucionesScript` con
    `TotalFiltradaSAP = length(ListaFiltradaSAP)`, `TotalCandidatas =
    length(ListaCandidatas)`, para que quede visible cuántas se
    descartaron solo por vencer el plazo de 3 días.

### Etapa B — Ejecutar la conversión en ME59N con la lista filtrada

Confirmado con tu script real de `ME59N`: **sí acepta pegar la lista
completa de Solpeds candidatas de una sola vez**, igual que `ME5A` — no
hace falta un `Loop for each` entrando una por una.

1. **SAP – Run transaction**: `ME59N`.
2. **SAP – Set field value** en la selección múltiple de Grupo de compras
   (`S_EKGRP`) = `005` (igual que en `ME5A`).
3. **SAP – Set field value** en la selección múltiple de Centro
   (`S_WERKS`), 3 líneas: `10*`, `15*`, `16*` (igual que en `ME5A`).
4. **Pegar la lista de candidatas en "Solicitud de pedido" (`S_BANFN`)**:
   - **SAP – Press button** `btn%_S_BANFN_%_APP_%-VALU_PUSH` (abre el
     popup de selección múltiple del campo).
   - Antes de este paso, poner en el portapapeles del sistema (acción
     **"Set clipboard text"** de Power Automate Desktop) la columna
     `Solicitud de pedido` de `ListaCandidatas`, una por línea.
   - **SAP – Press button** `btn[24]` dentro del popup ("Subir desde
     portapapeles" / *Upload from clipboard*, `Shift+F12`) — esto pega
     todos los números de una sola vez.
   - **SAP – Press button** `btn[8]` para confirmar los valores pegados.
5. **SAP – Run current transaction** (`F8` / `btn[8]` en la barra
   principal) — **este es el paso que falta grabar en tu script** (lo que
   marcaste como pendiente). Debería ser el mismo patrón que ya usas en
   `ME5A`: `session.findById("wnd[0]/tbar[1]/btn[8]").press`. Avísame si
   al ejecutar aparece algún paso intermedio (p. ej. una pantalla de
   confirmación antes de la conversión masiva) para documentarlo tal cual.
6. **SAP – Get table from SAP screen** sobre el log de aplicación
   resultante: columnas `PedidoAbierto`, `PosPedidoAbierto`, `Solped`,
   `PosSolped`, `Material`, ícono (🔴/🔺), `MensajeSAP`, `ClaseMensaje`,
   `NumeroMensaje` — mismo formato que el log que compartiste.
7. **Filter data table**: te quedas solo con las filas 🔴 (icono rojo) →
   variable `ListaErrores` (las 🔺 se descartan o se guardan aparte como
   advertencia, ver clasificación abajo). Las Solpeds que no aparecen con
   ningún 🔴 asociado van a `ListaExitos`.
8. **Return values from flow** (acción de cierre del flow de escritorio):
   `ListaExitos`, `ListaErrores`, `TotalFiltradaSAP`, `TotalCandidatas`.

---

## Flow 3 — "Enviar Contratos a ISA" (cloud, invocado desde el botón)

**Tipo:** Automated cloud flow
**Trigger:** **Power Apps (V2)** (sin parámetros)

**Acciones:**
1. **Run a flow built with Power Automate for desktop** → flow de
   escritorio que refresca `ME3M`, `Consumo`, `MB51`, `ME5A` y recalcula
   `ContratosSaldo` (mismo patrón que el Flow 4 de abajo).
2. **List rows** (Dataverse) sobre `ContratosSaldo`.
3. **Create CSV table** o **Populate a Microsoft Excel template** —
   plantilla liviana con las mismas columnas que ya viste en
   `Contratos_sem26.xlsx` (41 columnas, sin las de trazabilidad interna).
4. **Create file** en la biblioteca de SharePoint acordada con ISA.
5. **Send an email (V2)** a Isa con el archivo adjunto o el enlace de
   SharePoint, más un resumen: cuántos contratos con `PorAmpliar = "Sí"` y
   cuántos con diferencia de estabilización (`Pendiente <> 0` en el pivot).
6. **Respond to a PowerApp or flow** (opcional) confirmando el envío.

---

## Flow 4 — "Actualizar EstadoStockSS" / "Actualizar ContratosSaldo" (Desktop)

Mismo patrón que el Flow 2b, adaptado a cada reporte:

**Para `EstadoStockSS`:**
1. Abrir/adjuntar sesión SAP.
2. Ejecutar y exportar `SP`, `OC`, `ME2N`, `MB52` (Stock en piso),
   Consumos, Ingresos, Reservas, Contratos — una acción **SAP – Export
   data to Excel/variable** por cada una.
3. **Merge data tables** (o varias acciones **Join/Lookup** sucesivas) por
   la clave Centro+Material, replicando el cruce de la hoja `BD`.
4. Calcular `StatusStock` con una acción **If** por fila (o **Set variable**
   con expresión): `Quiebre` si `StockActual < StockSeguridad`, si no
   comparar contra `StockMáximo` para decidir `En stock` vs `Sobre Stock`.
5. **Apply to each** sobre el resultado → **Update/insert a row**
   (Dataverse, upsert) en `EstadoStockSS`, usando `CentroMaterial` como
   clave alternativa.
6. **Return values from flow**: `TotalFilas`, `TotalQuiebres` (para el log
   de `EjecucionesScript`).

**Para `ContratosSaldo`:** igual estructura, cambiando el origen (`ME3M`,
`Consumo`, `MB51`, `ME5A`) y el cálculo de `PorAmpliar`
(`Sí` si `SaldoCantidad < 0`).

Ambos, al terminar, deberían **Add a new row** en `EjecucionesScript` con
`TipoScript`, `EstadoEjecucion` y `LogResultado` (para que se vea en la
pantalla "Consultar estado").
