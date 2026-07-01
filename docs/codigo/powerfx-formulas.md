# Fórmulas Power Fx por botón/pantalla

Código listo para pegar en la barra de fórmulas de Power Apps Studio
(selecciona el control → propiedad `OnSelect`, `OnVisible`, `Items`, etc.).
Asume que ya conectaste las 6 tablas de Dataverse (Paso 1 de la guía de
implementación) con estos nombres lógicos en la app:

`Solpeds_OC_Spot`, `EstadoStockSS`, `ContratosSaldo`, `ErroresME59N`,
`EjecucionesScript`, `Reportes`.

Ajusta los nombres de columna si Dataverse los generó distinto al crear las
tablas (Power Apps a veces antepone el prefijo de tu solución, ej.
`cr123_numerosolped`) — revísalo en el panel de datos antes de pegar.

---

## 1. Navegación (sidebar)

En cada botón del menú lateral, `OnSelect`:

```powerfx
// Botón "Registrar Solped"
Navigate(RegistrarSolped, ScreenTransition.Fade)

// Botón "Generar Solped (ME59N)"
Navigate(PantallaME59N, ScreenTransition.Fade)

// Botón "Radar de Riesgos"
Navigate(Radar, ScreenTransition.Fade)

// Botón "Stockflow"
Navigate(Stockflow, ScreenTransition.Fade)

// Botón "Contratos -> ISA"
Navigate(ContratosISA, ScreenTransition.Fade)

// Botón "Consultar estado"
Navigate(ConsultarEstado, ScreenTransition.Fade)
```

---

## 2. Pantalla "Registrar Solped → OC Spot"

Controles esperados: `TxtNumeroSolped`, `TxtMaterial`, `TxtCantidad`,
`TxtCentroCosto`, `TxtComentarios` (inputs de texto/número).

**Botón "Guardar y notificar a CoE Compras" → `OnSelect`:**

```powerfx
// 1) Validación mínima antes de guardar
If(
    IsBlank(TxtNumeroSolped.Text) || IsBlank(TxtMaterial.Text),
    Notify("Completa al menos Nº Solped y Material.", NotificationType.Warning),
    // 2) Guarda la fila en Dataverse
    Patch(
        Solpeds_OC_Spot,
        Defaults(Solpeds_OC_Spot),
        {
            NumeroSolped: TxtNumeroSolped.Text,
            Material: TxtMaterial.Text,
            Cantidad: Value(TxtCantidad.Text),
            CentroCosto: TxtCentroCosto.Text,
            SolicitadoPor: User(),
            Estado: {Value: "Registrado"},
            FechaRegistro: Today(),
            Comentarios: TxtComentarios.Text
        }
    );
    // 3) La notificación al CoE de Compras la dispara SOLO el flow
    //    "Notificar nueva Solped" (trigger: fila agregada en Dataverse).
    //    No hace falta llamarlo aquí. Ver docs/codigo/flujos-power-automate.md
    Notify("Solped registrada. Se notificará al CoE de Compras.", NotificationType.Success);
    Reset(TxtNumeroSolped); Reset(TxtMaterial); Reset(TxtCantidad);
    Reset(TxtCentroCosto); Reset(TxtComentarios)
)
```

---

## 3. Pantalla "Generar Solped automáticas (ME59N)"

Controles esperados: `BtnEjecutarUN1`, `BtnEjecutarUN2`, `LblEstado`,
`GaleriaErroresME59N`, `KpiOK`, `KpiError`.

**Botón "Ejecutar ME59N — UN1" → `OnSelect`:**

```powerfx
// Llama al flow "padre" (creado en Power Automate, ver guía Paso 3.3)
Set(varResultadoME59N, 'Ejecutar ME59N'.Run("UN1"));

Notify(
    "ME59N UN1: " & varResultadoME59N.convertidas & " convertidas, " &
    varResultadoME59N.errores & " con error.",
    NotificationType.Information
)
```

*(`'Ejecutar ME59N'` es el nombre del flow tal como aparece en el panel
Data → Power Automate de la app; Power Apps lo muestra con comillas simples
si tiene espacios. El flow debe devolver `convertidas` y `errores` como
salidas — configúralo en el paso "Respond to a Power App or flow".)*

**Botón "Ejecutar ME59N — UN2" → `OnSelect`:** igual que arriba, cambia
`"UN1"` por `"UN2"`.

**Galería de errores → `Items`:**

```powerfx
Filter(ErroresME59N, UnidadNegocio.Value = "UN1", Estado.Value = "Pendiente")
```

*(cambia el filtro de `UnidadNegocio` según qué botón se ejecutó por
último, o usa una variable `varUNSeleccionada` para no repetir pantallas)*

**KPIs (texto) → `Text`:**

```powerfx
// KpiOK.Text
Text(CountRows(Filter(Solpeds_OC_Spot, Estado.Value = "Convertido a OC", Modified >= Today())))

// KpiError.Text
Text(CountRows(Filter(ErroresME59N, Estado.Value = "Pendiente")))
```

---

## 4. Pantalla "Radar de Riesgos"

**Galería principal → `Items`** (combina las 3 fuentes; en Power Apps real
esto se hace mejor con 3 galerías separadas o una vista/consulta en
Dataverse, pero como aproximación rápida con `EstadoStockSS`):

```powerfx
SortByColumns(
    Filter(EstadoStockSS, StatusStock.Value = "Quiebre"),
    "Diferencia",
    SortOrder.Ascending
)
```

**KPI "Críticas" → `Text`:**

```powerfx
Text(CountRows(Filter(EstadoStockSS, StatusStock.Value = "Quiebre")))
```

**Botón de acción por fila (ej. "Generar OC") → `OnSelect`** (dentro de la
plantilla de la galería, usa `ThisItem`):

```powerfx
Patch(EstadoStockSS, ThisItem, {UltimaAccion: "Generar OC solicitada por " & User().FullName & " el " & Text(Now())});
Notify("Acción registrada para " & ThisItem.Material, NotificationType.Success)
```

*(agrega la columna `UltimaAccion` (texto) a `EstadoStockSS` si quieres
dejar este rastro; si no, omite el `Patch` y deja solo la notificación /
llamada al flow de notificación correspondiente)*

---

## 5. Pantalla "Stockflow"

**Galería por familia → `Items`:** viene de un resumen agregado; lo más
simple en Power Fx (sin crear una vista aparte en Dataverse) es agrupar en
la propia app:

```powerfx
AddColumns(
    GroupBy(EstadoStockSS, "TipoMaterial", "Grupo"),
    "PctCumplStockSeg",
    // Ejemplo simplificado: % de filas que NO están en Quiebre
    CountRows(Filter(Grupo, StatusStock.Value <> "Quiebre")) / CountRows(Grupo)
)
```

*(si el volumen de filas es grande, es mejor calcular este agregado en el
propio flow de Power Automate Desktop al hacer el upsert, y guardarlo en
una tabla `StockflowResumen` aparte — más rápido de leer desde la app)*

---

## 6. Pantalla "Contratos → ISA"

**Galería → `Items`:**

```powerfx
Filter(ContratosSaldo, PorAmpliar.Value = "Sí")
```

**Botón "Generar y enviar archivo a ISA" → `OnSelect`:**

```powerfx
Set(varResultadoISA, 'Enviar Contratos a ISA'.Run());
Notify("Archivo de contratos generado y enviado a ISA.", NotificationType.Success)
```

---

## 7. Pantalla "Consultar estado"

**Galería de Solpeds → `Items`** (con buscador `TxtBuscarSolped`):

```powerfx
Filter(
    Solpeds_OC_Spot,
    IsBlank(TxtBuscarSolped.Text) || StartsWith(NumeroSolped, TxtBuscarSolped.Text)
)
```

**Galería de ejecuciones de script → `Items`:**

```powerfx
SortByColumns(EjecucionesScript, "FechaEjecucion", SortOrder.Descending)
```

**Galería de reportes → `Items`:**

```powerfx
SortByColumns(Reportes, "FechaGeneracion", SortOrder.Descending)
```

---

## Notas generales

- `'Nombre del flow'.Run(...)` requiere que el flow esté agregado a la app
  desde el panel **Data → Power Automate** (o desde el propio botón,
  `Action → Power Automate → + Add flow`) antes de poder llamarlo así.
- Los `Notify(...)` son solo mensajes en pantalla (toast de Power Apps);
  no reemplazan la notificación real a Teams/correo, que vive en el flow
  (ver `docs/codigo/flujos-power-automate.md`).
- Si al conectar Dataverse los nombres de columna aparecen distintos a los
  usados aquí (con prefijo de la solución), usa el autocompletar de la
  barra de fórmulas (Ctrl+Espacio) para ver el nombre real y ajusta.
