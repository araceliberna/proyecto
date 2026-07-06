' =====================================================================
' ME59N_Automatico.vbs
'
' Encadena tus 3 scripts reales (ME5A + 2 filtros del ALV + ME59N) en
' uno solo, y agrega la parte que faltaba automatizar: el calculo del
' 4to filtro (antiguedad <= 3 dias) y el paso final de "Ejecutar".
'
' IMPORTANTE - leelo antes de correrlo:
' Los bloques marcados "*** TAL CUAL LO GRABASTE ***" son copia textual
' de los scripts que me pasaste -- no los toque. Los bloques marcados
' "*** LOGICA NUEVA ***" son codigo que yo escribi y que NO ha sido
' probado contra tu SAP real (no tengo forma de probarlo desde aqui).
' Corre este script primero en un centro/lote chico o con
' MsgBox de verificacion antes de dejarlo correr solo.
'
' Requisitos: SAP Logon abierto y con la sesion ya conectada, scripting
' habilitado (igual que para tus .vbs actuales). Doble clic para correr.
' =====================================================================

Option Explicit

Dim app, connection, session
Dim SapGuiAuto

' ---------------------------------------------------------------
' 0) Conectarse a la sesion de SAP ya abierta *** TAL CUAL LO GRABASTE ***
' ---------------------------------------------------------------
If Not IsObject(app) Then
    Set SapGuiAuto = GetObject("SAPGUISERVER")
    Set app = SapGuiAuto.GetScriptingEngine
End If
If Not IsObject(connection) Then
    Set connection = app.Children(0)
End If
If Not IsObject(session) Then
    Set session = connection.Children(0)
End If
If IsObject(WScript) Then
    WScript.ConnectObject session, "on"
    WScript.ConnectObject app, "on"
End If

session.findById("wnd[0]").resizeWorkingPane 124, 16, False

' ---------------------------------------------------------------
' *** LOGICA NUEVA *** -- Entrar a ME5A explicitamente.
' Esto faltaba: tu script original asumia que ya estabas parada
' dentro de ME5A cuando lo corrias a mano. Como este script encadena
' todo desde cero, hay que navegar primero.
' ---------------------------------------------------------------
session.findById("wnd[0]/tbar[0]/okcd").text = "/nME5A"
session.findById("wnd[0]").sendVKey 0

' ---------------------------------------------------------------
' 1) ME5A -- filtros de seleccion *** TAL CUAL LO GRABASTE ***
'    (EKGRP=005, Centro=10*/15*/16*, Estado=N)
' ---------------------------------------------------------------
session.findById("wnd[0]/usr/btn%_BA_EKGRP_%_APP_%-VALU_PUSH").press
session.findById("wnd[1]/usr/tabsTAB_STRIP/tabpSIVA/ssubSCREEN_HEADER:SAPLALDB:3010/tblSAPLALDBSINGLE/ctxtRSCSEL_255-SLOW_I[1,0]").text = "005"
session.findById("wnd[1]/usr/tabsTAB_STRIP/tabpSIVA/ssubSCREEN_HEADER:SAPLALDB:3010/tblSAPLALDBSINGLE/ctxtRSCSEL_255-SLOW_I[1,0]").caretPosition = 3
session.findById("wnd[1]/tbar[0]/btn[8]").press

session.findById("wnd[0]/usr/btn%_S_WERKS_%_APP_%-VALU_PUSH").press
session.findById("wnd[1]/usr/tabsTAB_STRIP/tabpSIVA/ssubSCREEN_HEADER:SAPLALDB:3010/tblSAPLALDBSINGLE/ctxtRSCSEL_255-SLOW_I[1,0]").text = "10*"
session.findById("wnd[1]/usr/tabsTAB_STRIP/tabpSIVA/ssubSCREEN_HEADER:SAPLALDB:3010/tblSAPLALDBSINGLE/ctxtRSCSEL_255-SLOW_I[1,1]").text = "15*"
session.findById("wnd[1]/usr/tabsTAB_STRIP/tabpSIVA/ssubSCREEN_HEADER:SAPLALDB:3010/tblSAPLALDBSINGLE/ctxtRSCSEL_255-SLOW_I[1,2]").text = "16*"
session.findById("wnd[1]/usr/tabsTAB_STRIP/tabpSIVA/ssubSCREEN_HEADER:SAPLALDB:3010/tblSAPLALDBSINGLE/ctxtRSCSEL_255-SLOW_I[1,2]").setFocus
session.findById("wnd[1]/usr/tabsTAB_STRIP/tabpSIVA/ssubSCREEN_HEADER:SAPLALDB:3010/tblSAPLALDBSINGLE/ctxtRSCSEL_255-SLOW_I[1,2]").caretPosition = 3
session.findById("wnd[1]/tbar[0]/btn[8]").press

session.findById("wnd[0]/usr/ctxtS_STATU-LOW").text = "N"
session.findById("wnd[0]/usr/ctxtS_STATU-LOW").setFocus
session.findById("wnd[0]/usr/ctxtS_STATU-LOW").caretPosition = 1
session.findById("wnd[0]/tbar[1]/btn[8]").press

' ---------------------------------------------------------------
' 1b) Elegir el layout guardado (fila 17) *** TAL CUAL LO GRABASTE ***
'     Esto se me habia quedado fuera -- sin este layout, columnas como
'     DISPO no existen en la grilla por defecto y el filtro de abajo
'     falla con "El parametro no es correcto".
' ---------------------------------------------------------------
session.findById("wnd[0]/tbar[1]/btn[33]").press
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_LAYOUT_CHOOSE:0500/cntlD500_CONTAINER/shellcont/shell").currentCellRow = 17
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_LAYOUT_CHOOSE:0500/cntlD500_CONTAINER/shellcont/shell").firstVisibleRow = 14
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_LAYOUT_CHOOSE:0500/cntlD500_CONTAINER/shellcont/shell").selectedRows = "17"
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_LAYOUT_CHOOSE:0500/cntlD500_CONTAINER/shellcont/shell").clickCurrentCell

' ---------------------------------------------------------------
' 2) Filtro ALV: excluir Indicador de borrado / Concluida
'    *** TAL CUAL LO GRABASTE ***
'    OJO: el paso "sendVKey 4" dentro de wnd[3] es tu grabacion literal;
'    no capturo explicitamente que valor tecleaste ahi (probablemente
'    usaste F4/ayuda de valores y elegiste algo de una lista). Si al
'    correr esto ves que NO quedo excluido correctamente, es la parte a
'    re-grabar con mas detalle (abre esa ventana paso a paso, sin
'    saltos, y vuelve a grabar solo ese tramo).
' ---------------------------------------------------------------
session.findById("wnd[0]/usr/cntlGRID1/shellcont/shell").firstVisibleColumn = "DISPO"
session.findById("wnd[0]/tbar[1]/btn[29]").press
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/cntlCONTAINER1_FILT/shellcont/shell").firstVisibleRow = 108
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/cntlCONTAINER1_FILT/shellcont/shell").pressToolbarButton "&FIND"
session.findById("wnd[2]/usr/txtGS_SEARCH-VALUE").text = "indicad"
session.findById("wnd[2]/usr/txtGS_SEARCH-VALUE").caretPosition = 7
session.findById("wnd[2]").sendVKey 0
session.findById("wnd[2]").close
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/btnAPP_WL_SING").press
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/cntlCONTAINER1_FILT/shellcont/shell").selectedRows = "30"
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/btnAPP_WL_SING").press
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/cntlCONTAINER1_FILT/shellcont/shell").firstVisibleRow = 0
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/btn600_BUTTON").press
session.findById("wnd[2]/usr/ssub%_SUBSCREEN_FREESEL:SAPLSSEL:1105/btn%_%%DYN001_%_APP_%-VALU_PUSH").press
session.findById("wnd[3]/usr/tabsTAB_STRIP/tabpNOSV").select
session.findById("wnd[3]").sendVKey 4
session.findById("wnd[3]/tbar[0]/btn[8]").press
session.findById("wnd[2]/usr/ssub%_SUBSCREEN_FREESEL:SAPLSSEL:1105/btn%_%%DYN002_%_APP_%-VALU_PUSH").press
session.findById("wnd[3]/usr/tabsTAB_STRIP/tabpNOSV").select
session.findById("wnd[3]").sendVKey 4
session.findById("wnd[3]/tbar[0]/btn[8]").press
session.findById("wnd[2]/tbar[0]/btn[0]").press

' ---------------------------------------------------------------
' 3) Filtro ALV: excluir Contrato marco vacio *** TAL CUAL LO GRABASTE ***
' ---------------------------------------------------------------
session.findById("wnd[0]/tbar[1]/btn[29]").press
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/cntlCONTAINER1_FILT/shellcont/shell").currentCellRow = 7
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/cntlCONTAINER1_FILT/shellcont/shell").selectedRows = "7"
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/btnAPP_WL_SING").press
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/cntlCONTAINER2_FILT/shellcont/shell").currentCellRow = 2
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/cntlCONTAINER2_FILT/shellcont/shell").selectedRows = "2"
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/cntlCONTAINER2_FILT/shellcont/shell").doubleClickCurrentCell
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/cntlCONTAINER1_FILT/shellcont/shell").selectedRows = "7"
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/cntlCONTAINER1_FILT/shellcont/shell").doubleClickCurrentCell
session.findById("wnd[1]/usr/subSUB_CONFIGURATION:SAPLSALV_CUL_FILTER_CRITERIA:0600/btn600_BUTTON").press
session.findById("wnd[2]/usr/ssub%_SUBSCREEN_FREESEL:SAPLSSEL:1105/btn%_%%DYN001_%_APP_%-VALU_PUSH").press
session.findById("wnd[3]/usr/tabsTAB_STRIP/tabpNOSV").select
session.findById("wnd[3]/usr/tabsTAB_STRIP/tabpNOSV/ssubSCREEN_HEADER:SAPLALDB:3030/tblSAPLALDBSINGLE_E/btnRSCSEL_255-SOP_E[0,0]").setFocus
session.findById("wnd[3]/usr/tabsTAB_STRIP/tabpNOSV/ssubSCREEN_HEADER:SAPLALDB:3030/tblSAPLALDBSINGLE_E/btnRSCSEL_255-SOP_E[0,0]").press
session.findById("wnd[4]/usr/cntlOPTION_CONTAINER/shellcont/shell").doubleClickCurrentCell
session.findById("wnd[3]/tbar[0]/btn[8]").press
session.findById("wnd[2]/tbar[0]/btn[0]").press
session.findById("wnd[0]/usr/cntlGRID1/shellcont/shell").firstVisibleRow = 107
session.findById("wnd[0]/usr/cntlGRID1/shellcont/shell").firstVisibleRow = 0

' ---------------------------------------------------------------
' 4) *** LOGICA NUEVA *** -- Traer la tabla filtrada a memoria
'    (aqui ya deberian estar aplicados los 3 filtros de arriba)
'
'    OJO: los nombres de columna tecnica (BANFN, WERKS, MATNR, KONNR,
'    FRGDT, AEDAT) son mi mejor suposicion segun los campos estandar de
'    SAP para Solped/EBAN -- pero NO los he verificado contra tu layout
'    real. Si al correr esto da error "columna no encontrada", clic
'    derecho sobre el encabezado de esa columna en el grid > "Ayuda
'    tecnica de campo" para ver el nombre real, y reemplazalo aqui.
' ---------------------------------------------------------------
Dim grid, totalFilas, i
Set grid = session.findById("wnd[0]/usr/cntlGRID1/shellcont/shell")
totalFilas = grid.RowCount

Const COL_SOLPED   = "BANFN"   ' Solicitud de pedido (verificar)
Const COL_CENTRO   = "WERKS"   ' Centro (verificar)
Const COL_MATERIAL = "MATNR"   ' Material (verificar)
Const COL_CONTRATO = "KONNR"   ' Contrato marco (verificar)
Const COL_FECHALIB = "FRGDT"   ' Fecha de liberacion (verificar)
Const COL_MODIF    = "AEDAT"   ' Modificado el (verificar)

Dim tabla()
ReDim tabla(totalFilas - 1, 5)
For i = 0 To totalFilas - 1
    tabla(i, 0) = grid.GetCellValue(i, COL_SOLPED)
    tabla(i, 1) = grid.GetCellValue(i, COL_CENTRO)
    tabla(i, 2) = grid.GetCellValue(i, COL_MATERIAL)
    tabla(i, 3) = grid.GetCellValue(i, COL_CONTRATO)
    tabla(i, 4) = grid.GetCellValue(i, COL_FECHALIB)
    tabla(i, 5) = grid.GetCellValue(i, COL_MODIF)
Next

' ---------------------------------------------------------------
' 5) *** LOGICA NUEVA *** -- 4to filtro: antiguedad <= 3 dias
'    (esto era el paso manual que pediste automatizar)
' ---------------------------------------------------------------
Dim hoy, listaFinal(), totalCandidatas, exclDias
Dim fLib, fMod, fRef, dias

hoy = Date
ReDim listaFinal(totalFilas)
totalCandidatas = 0
exclDias = 0

For i = 0 To totalFilas - 1
    fLib = ParseFechaSAP(tabla(i, 4))
    fMod = ParseFechaSAP(tabla(i, 5))

    If IsDate(fLib) And IsDate(fMod) Then
        If CDate(fLib) > CDate(fMod) Then fRef = fLib Else fRef = fMod
    ElseIf IsDate(fLib) Then
        fRef = fLib
    ElseIf IsDate(fMod) Then
        fRef = fMod
    Else
        fRef = Empty
    End If

    If IsDate(fRef) Then
        dias = DateDiff("d", CDate(fRef), hoy)
        If dias <= 3 Then
            listaFinal(totalCandidatas) = tabla(i, 0)
            totalCandidatas = totalCandidatas + 1
        Else
            exclDias = exclDias + 1
        End If
    Else
        listaFinal(totalCandidatas) = tabla(i, 0)
        totalCandidatas = totalCandidatas + 1
    End If
Next

If totalCandidatas = 0 Then
    MsgBox "No quedo ninguna Solped candidata tras el filtro de antiguedad (3 dias)." & vbCrLf & _
           "Filas que pasaron los 3 filtros de SAP: " & totalFilas & vbCrLf & _
           "Excluidas por antiguedad: " & exclDias, vbExclamation, "ME59N Automatico"
    WScript.Quit
End If

' ---------------------------------------------------------------
' 6) *** LOGICA NUEVA *** -- Copiar la lista final al portapapeles
' ---------------------------------------------------------------
Dim listaTexto, objIE, ta
listaTexto = ""
For i = 0 To totalCandidatas - 1
    listaTexto = listaTexto & listaFinal(i) & vbCrLf
Next

Set objIE = CreateObject("htmlfile")
Set ta = objIE.createElement("textarea")
objIE.appendChild ta
ta.innerText = listaTexto
ta.Select
objIE.execCommand "Copy"

Dim respuesta
respuesta = MsgBox(totalCandidatas & " Solpeds candidatas copiadas al portapapeles." & vbCrLf & _
       "(de " & totalFilas & " que pasaron los 3 filtros de SAP; " & exclDias & " se excluyeron por pasar los 3 dias)" & vbCrLf & vbCrLf & _
       "Continuar y abrir ME59N para pegarlas y ejecutar?", vbYesNo + vbQuestion, "ME59N Automatico")

If respuesta = vbNo Then
    WScript.Quit
End If

' ---------------------------------------------------------------
' *** LOGICA NUEVA *** -- Entrar a ME59N explicitamente (mismo motivo
' que con ME5A: hay que navegar, no asumir que ya estas ahi).
' ---------------------------------------------------------------
session.findById("wnd[0]/tbar[0]/okcd").text = "/nME59N"
session.findById("wnd[0]").sendVKey 0

' ---------------------------------------------------------------
' 7) ME59N -- filtros y pegado *** TAL CUAL LO GRABASTE ***
' ---------------------------------------------------------------
session.findById("wnd[0]/usr/btn%_S_EKGRP_%_APP_%-VALU_PUSH").press
session.findById("wnd[1]/usr/tabsTAB_STRIP/tabpSIVA/ssubSCREEN_HEADER:SAPLALDB:3010/tblSAPLALDBSINGLE/ctxtRSCSEL_255-SLOW_I[1,0]").text = "005"
session.findById("wnd[1]/tbar[0]/btn[8]").press

session.findById("wnd[0]/usr/btn%_S_WERKS_%_APP_%-VALU_PUSH").press
session.findById("wnd[1]/usr/tabsTAB_STRIP/tabpSIVA/ssubSCREEN_HEADER:SAPLALDB:3010/tblSAPLALDBSINGLE/ctxtRSCSEL_255-SLOW_I[1,0]").text = "10*"
session.findById("wnd[1]/usr/tabsTAB_STRIP/tabpSIVA/ssubSCREEN_HEADER:SAPLALDB:3010/tblSAPLALDBSINGLE/ctxtRSCSEL_255-SLOW_I[1,1]").text = "15*"
session.findById("wnd[1]/usr/tabsTAB_STRIP/tabpSIVA/ssubSCREEN_HEADER:SAPLALDB:3010/tblSAPLALDBSINGLE/ctxtRSCSEL_255-SLOW_I[1,2]").text = "16*"
session.findById("wnd[1]/tbar[0]/btn[8]").press

session.findById("wnd[0]/usr/btn%_S_BANFN_%_APP_%-VALU_PUSH").press
session.findById("wnd[1]/tbar[0]/btn[24]").press
session.findById("wnd[1]/tbar[0]/btn[8]").press

' ---------------------------------------------------------------
' 8) *** LOGICA NUEVA *** -- Ejecutar (este era el paso que dijiste
'    que faltaba grabar). Uso el mismo patron que tu ME5A (btn[8] de
'    la barra de aplicacion) -- verificalo la primera vez antes de
'    automatizarlo sin supervision.
' ---------------------------------------------------------------
session.findById("wnd[0]/tbar[1]/btn[8]").press

MsgBox "Se ejecuto ME59N con " & totalCandidatas & " Solpeds candidatas." & vbCrLf & _
       "Revisa el log de resultado en pantalla (los iconos [ROJO] son las que fallaron).", _
       vbInformation, "ME59N Automatico"

' =====================================================================
' Funcion auxiliar *** LOGICA NUEVA *** -- interpreta fechas SAP tipicas
' (dd.mm.yyyy o dd/mm/yyyy). Ajusta si tu layout las muestra distinto.
' =====================================================================
Function ParseFechaSAP(valor)
    Dim s
    s = Trim(CStr(valor))
    If s = "" Then
        ParseFechaSAP = Empty
        Exit Function
    End If
    s = Replace(s, ".", "/")
    On Error Resume Next
    ParseFechaSAP = CDate(s)
    If Err.Number <> 0 Then
        ParseFechaSAP = Empty
        Err.Clear
    End If
    On Error Goto 0
End Function

' =====================================================================
' PENDIENTE (no incluido todavia): leer y clasificar el LOG de errores
' que aparece despues del paso 8. No tengo los IDs de esa pantalla
' (solo vi una captura, no un script grabado). Para completarlo:
' abre el Scripting Recorder de SAP, entra a esa pantalla de log,
' expande/lee un par de filas, guarda el .vbs grabado y pasamelo -- lo
' agrego a este mismo archivo como el paso 9.
' =====================================================================
