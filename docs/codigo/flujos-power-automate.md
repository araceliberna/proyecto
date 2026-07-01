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
   (tabla) y `ListaErrores` (tabla, con columnas `Solped`, `Posicion`,
   `Material`, `MensajeSAP`).
3. **Apply to each** sobre `ListaExitos`:
   - **Update a row** (Dataverse) en `Solpeds_OC_Spot` — busca por
     `NumeroSolped` igual al ítem actual, set `Estado = "Convertido a OC"`,
     `NumeroOCSpot = <ítem.OC>`.
4. **Apply to each** sobre `ListaErrores`:
   - **Switch** sobre el contenido de `MensajeSAP` (usar expresión
     `contains(items('Apply_to_each')?['MensajeSAP'], 'bloqueado')`, etc.
     — ver tabla de clasificación más abajo) → variable `Categoria`.
   - **Add a new row** (Dataverse) en `ErroresME59N` con `NumeroSolped`,
     `Posicion`, `Material`, `UnidadNegocio`, `MensajeSAP`, `Categoria`,
     `Estado = "Pendiente"`.
   - **Condition** sobre `Categoria`:
     - `"Proveedor bloqueado"` → **Post message in a chat or channel**
       al canal de Compras/Finanzas.
     - `"Sin fuente de suministro"` u `"Dato maestro"` → notificar al
       Planeador (dueño de la Solped, `SolicitadoPor`).
     - Resto (`"Otro"`) → notificar al canal general de PMI para revisión
       manual.
5. **Response** (si el trigger es Power Apps V2, usa la acción
   **"Respond to a PowerApp or flow"**) con dos salidas numéricas:
   `convertidas = length(ListaExitos)`, `errores = length(ListaErrores)`.
   Esto es lo que Power Apps recibe en `varResultadoME59N.convertidas` /
   `.errores` (ver `docs/codigo/powerfx-formulas.md`, sección 3).

### Tabla de clasificación de errores (bloque "Switch")

Cópiala tal cual como reglas `contains(MensajeSAP, "...")` dentro del
Switch/If — y ajústala cuando me pases el listado real de mensajes de tu
`ME59N`:

| Si el mensaje SAP contiene... | Categoría | Notificar a |
|---|---|---|
| `"bloqueado"` | Proveedor bloqueado | Compras / Finanzas |
| `"fuente de suministro"` | Sin fuente de suministro | Planeador |
| `"información de compras"` / `"registro info"` | Dato maestro | Planeador |
| `"unidad de medida"` / `"UM"` | Diferencia UM | Planeador |
| (ninguna de las anteriores) | Otro | Canal PMI (revisión manual) |

---

## Flow 2b — "ME59N - Conversion Masiva" (Power Automate **Desktop**)

Este corre en tu PC (o VM) con SAP GUI abierto, vía Power Automate Desktop.
Secuencia de acciones (catálogo "SAP" del diseñador de escritorio):

1. **SAP – Launch SAP Logon and log on to SAP** (o **Attach to running
   instance** si ya tienes sesión abierta).
2. **SAP – Run transaction**: `ME59N`.
3. **SAP – Set field value** / **Send SAP shortcut** para aplicar el
   filtro por unidad de negocio (`UnidadNegocio`, parámetro recibido del
   flow cloud) y demás criterios (Solpeds liberadas, sin bloqueo, etc.)
4. **SAP – Run current transaction** (ejecutar la selección/conversión
   masiva).
5. **SAP – Get table from SAP screen** (o **Export data to Excel**) sobre
   el log de aplicación resultante: esto te da una tabla con columnas tipo
   `Solped`, `Posición`, `Mensaje`, `Tipo` (éxito/error).
6. **Filter data table** dos veces: una para quedarte con las filas de
   éxito (`Tipo = Éxito`) → variable `ListaExitos`; otra con las de error
   (`Tipo = Error`) → variable `ListaErrores`.
7. **Return values from flow** (acción de cierre del flow de escritorio):
   `ListaExitos`, `ListaErrores`.

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
