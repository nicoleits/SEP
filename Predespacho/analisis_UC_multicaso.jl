using JuMP, HiGHS, XLSX, DataFrames, Plots, LinearAlgebra, Dates

# --- FUNCION GENERALIZADA PARA RESOLVER UC ---
function resolver_UC(tipo_caso, tipo_serie, archivo; nombre_caso="")
    # --- LECTURA DE DATOS ---
    if tipo_caso == 0
        datGen      =   XLSX.readdata(archivo,"Gen!C4:O12")
        datDem      =   XLSX.readdata(archivo,"dem!A4:J27")
        datLineas   =   XLSX.readdata(archivo,"Lineas!A4:G14")
        pEr = nothing
    else
        datGen      =   XLSX.readdata(archivo,"Gen!C4:O14")
        datDem      =   XLSX.readdata(archivo,"dem!A4:J27")
        datLineas   =   XLSX.readdata(archivo,"Lineas!A4:G14")
        
        # Leer datos de energía renovable
        rangos = Dict(
            1 => "ERV!C5:AB6", 2 => "ERV!C13:AB14", 3 => "ERV!C20:AB21",
            4 => "ERV!C27:AB28", 5 => "ERV!C35:AB36", 6 => "ERV!C42:AB43",
            7 => "ERV!C49:AB50", 8 => "ERV!C56:AB57", 9 => "ERV!C63:AB64"
        )
        
        # Leer datos de energía renovable
        datEr = XLSX.readdata(archivo, rangos[tipo_serie])
        
        # Las primeras 4 columnas son identificadores, el resto son horas
        pEr = datEr[:, 5:end]'  # pEr: horas x generadores
        
        # Verificar que el número de generadores renovables coincida con las columnas de pEr
        idx_renovables = findall(x -> x == 2, datGen[:,11])
        if length(idx_renovables) != size(pEr, 2)
            error("Número de generadores renovables ($(length(idx_renovables))) no coincide con columnas de pEr ($(size(pEr, 2)))")
        end
        
        # Verificar que el número de horas coincida con nT
        nT = size(pd, 1)
        if size(pEr, 1) != nT
            error("El número de horas en el perfil renovable ($(size(pEr, 1))) no coincide con el número de horas del modelo ($nT)")
        end
    end

    # --- PARÁMETROS ---
    busGen  = datGen[:,1]
    cv      = datGen[:,2]
    cEnc    = datGen[:,3]
    cApa    = datGen[:,4]
    pmax    = datGen[:,5]
    pmin    = datGen[:,6]
    t_up    = datGen[:,7]
    t_do    = datGen[:,8]
    R_up    = datGen[:,9]
    R_do    = datGen[:,10]
    tipoGen = datGen[:,11]
    aportaReserva = datGen[:,12]
    kReserva = datGen[:,13]
    pd     =  datDem[:,2:end]
    horasDia = datDem[:,1]
    Tmax    = datLineas[:,5]
    xij     = datLineas[:,4]
    fromTx  = datLineas[:,2]
    toTx    = datLineas[:,3]
    ng  = length(cv)
    nTx = length(Tmax)
    nBus = maximum(datLineas[:,[2,3]])

    # --- MATRICES DE INCIDENCIA ---
    A = zeros(nBus,nTx)
    for k in 1:nTx
        A[toTx[k],k]= -1
        A[fromTx[k],k]= 1
    end
    Ag = zeros(nBus,ng)
    for k in 1:ng
        Ag[busGen[k],k]=1
    end
    Ad = Matrix(Diagonal(ones(nBus)))
    Y = Matrix(Diagonal(1.0./xij))

    # --- MODELO UC ---
    m = Model(HiGHS.Optimizer)
    @variable(m,pg[1:ng,1:nT])
    @variable(m,rg[1:ng,1:nT])
    @variable(m,fTx[1:nTx,1:nT])
    @variable(m,theta[1:nBus,1:nT])
    @variable(m,ug[1:ng,1:nT], Bin)
    @variable(m,uEnc[1:ng,1:nT], Bin)
    @variable(m,uApa[1:ng,1:nT], Bin)
    @objective(m, Min, sum(sum( cv[i]*pg[i,j] +cEnc[i]*uEnc[i,j]+cApa[i]*uApa[i,j] for i in 1:ng) for j in 1:nT ))

    # --- RESTRICCIONES ---
    @constraint(m,balance[j in 1:nT], Ag*pg[:,j].-A*fTx[:,j] .== Ad*pd[j,:])
    @constraint(m,flujoTx[j=1:nT],fTx[:,j] .== Y*A'*theta[:,j])

    # Restricciones de límites máximos y mínimos para generadores
    if tipo_caso == 1 && pEr !== nothing
        # Encuentra los índices de los generadores renovables
        idx_renovables = findall(x -> x == 2, tipoGen)
        
        # Para cada generador renovable
        for (k, i) in enumerate(idx_renovables)
            @constraint(m, [j in 1:nT], pg[i,j]+rg[i,j] <= pEr[j,k]*ug[i,j])
            @constraint(m, [j in 1:nT], pg[i,j] >= pmin[i]*ug[i,j])
            @constraint(m, [j in 1:nT], rg[i,j] == 0)
        end
        
        # Para los demás generadores
        for i in setdiff(1:ng, idx_renovables)
            @constraint(m, [j in 1:nT], pg[i,j]+rg[i,j] <= pmax[i]*ug[i,j])
            @constraint(m, [j in 1:nT], pg[i,j] >= pmin[i]*ug[i,j])
        end
    else
        # Caso sin renovables
        for i in 1:ng
            @constraint(m, [j in 1:nT], pg[i,j]+rg[i,j] <= pmax[i]*ug[i,j])
            @constraint(m, [j in 1:nT], pg[i,j] >= pmin[i]*ug[i,j])
        end
    end

    @constraint(m, [i=1:nTx,j=1:nT],fTx[i,j]<=Tmax[i])
    @constraint(m, [i=1:nTx,j=1:nT],fTx[i,j]>=-Tmax[i])
    for i in 1:ng
        if aportaReserva[i]==1
            @constraint(m,[j in 1:nT],rg[i,j]>=kReserva[i]*pmax[i]*ug[i,j])
        end
    end
    @constraint(m,ramp_up[i in 1:ng,j in 2:nT], pg[i,j]-pg[i,j-1]+rg[i,j] <= R_up[i])
    @constraint(m,ramp_dw[i in 1:ng,j in 2:nT], pg[i,j]-pg[i,j-1] >= -R_do[i])
    @constraint(m, [i in 1:ng],ug[i,1] == uEnc[i,1]-uApa[i,1])
    @constraint(m, [i in 1:ng],ug[i,1] >= uEnc[i,1])
    @constraint(m, [i in 1:ng],1-ug[i,1] >= uApa[i,1])
    @constraint(m, [i in 1:ng,j in 2:nT], ug[i,j] == ug[i,j-1] + uEnc[i,j]-uApa[i,j] )
    for i in 1:ng
        rang1= t_up[i]:nT
        for j in rang1
            rang2 = (j-t_up[i]+1):j
            @constraint(m, ug[i,j] >= sum(uEnc[i,k] for k in rang2))
        end
    end
    @constraint(m,[i in 1:ng,j in 2:t_up[i]],ug[i,j] >= sum(uEnc[i,k] for k in 1:j))
    for i in 1:ng
        rang1= t_do[i]:nT
        for j in rang1
            rang2 = (j-t_do[i]+1):j
            @constraint(m, 1-ug[i,j] >= sum(uApa[i,k] for k in rang2))
        end
    end
    @constraint(m,[i in 1:ng,j in 2:t_do[i]],1-ug[i,j] >= sum(uApa[i,k] for k in 1:j))

    optimize!(m)

    # --- EXTRACCIÓN DE RESULTADOS ---
    costo_total = objective_value(m)
    ugSol = value.(ug)
    pgSol = value.(pg)
    rgSol = value.(rg)
    fTxSol = value.(fTx)
    cmg = zeros(nBus,nT)
    for i in 1:nT
        cmg[:,i] = dual.(balance[i])
    end

    # Vertimiento renovable
    vertimiento = 0.0
    if tipo_caso == 1 && pEr !== nothing
        idx_renovables = findall(x -> x == 2, tipoGen)
        for (k, i) in enumerate(idx_renovables)
            for j in 1:nT
                vertimiento += max(0, pEr[j, k] - pgSol[i, j])
            end
        end
    end

    # Líneas congestionadas
    lineas_cong = []
    for i in 1:nTx, j in 1:nT
        if abs(fTxSol[i,j]) >= Tmax[i]-1e-3
            push!(lineas_cong, (i,j))
        end
    end

    # Ingresos y egresos por central
    ingresos = [sum(cmg[busGen[i],:].*pgSol[i,:]) for i in 1:ng]
    egresos = [sum(cv[i]*pgSol[i,:] + cEnc[i]*value.(uEnc[i,:]) + cApa[i]*value.(uApa[i,:])) for i in 1:ng]

    # pg_renovable solo para renovables
    pg_renovable = tipo_caso==1 && pEr !== nothing ? [pgSol[i,:] for i in idx_renovables] : []

    return Dict(
        "nombre_caso" => nombre_caso,
        "costo_total" => costo_total,
        "cmg" => cmg,
        "ingresos" => ingresos,
        "egresos" => egresos,
        "commitment" => ugSol,
        "vertimiento" => vertimiento,
        "pg" => pgSol,
        "pg_renovable" => pg_renovable,
        "fTx" => fTxSol,
        "lineas_congestionadas" => lineas_cong,
        "horasDia" => horasDia,
        "busGen" => busGen,
        "pEr" => pEr,
        "tipoGen" => tipoGen
    )
end

# --- LISTA DE CASOS ---
casos = [
    ("Base", 0, 0, "Predespacho/UC_datEx8_sinER.xlsx"),
    ("Eólica Perfil 1", 1, 1, "Predespacho/UC_datEx8.xlsx"),
    ("Eólica Perfil 2", 1, 2, "Predespacho/UC_datEx8.xlsx"),
    ("Eólica Perfil 3", 1, 3, "Predespacho/UC_datEx8.xlsx"),
    ("FV Perfil 1", 1, 4, "Predespacho/UC_datEx8.xlsx"),
    ("FV Perfil 2", 1, 5, "Predespacho/UC_datEx8.xlsx"),
    ("FV Perfil 3", 1, 6, "Predespacho/UC_datEx8.xlsx"),
    ("Eólica+FV Perfil 1", 1, 7, "Predespacho/UC_datEx8.xlsx"),
    ("Eólica+FV Perfil 2", 1, 8, "Predespacho/UC_datEx8.xlsx"),
    ("Eólica+FV Perfil 3", 1, 9, "Predespacho/UC_datEx8.xlsx"),
]

resultados = []
for (nombre, tipo_caso, tipo_serie, archivo) in casos
    println("Resolviendo: $nombre")
    res = resolver_UC(tipo_caso, tipo_serie, archivo; nombre_caso=nombre)
    push!(resultados, res)
end

# --- TABLA RESUMEN ---
df = DataFrame(
    caso = [r["nombre_caso"] for r in resultados],
    costo_total = [r["costo_total"] for r in resultados],
    vertimiento = [r["vertimiento"] for r in resultados],
    lineas_congestionadas = [length(r["lineas_congestionadas"]) for r in resultados]
)

# --- GRAFICOS COMPARATIVOS ---
# Gráfico de costos totales
p1 = bar(df.caso, df.costo_total, 
    xlabel="Caso", 
    ylabel="Costo Total [USD]", 
    title="Comparación de Costos Totales",
    legend=false, 
    size=(900,400),
    color=:blue,
    yformatter=:scientific)
savefig(p1, "costos_totales.png")

# Gráfico de vertimiento
p2 = bar(df.caso, df.vertimiento, 
    xlabel="Caso", 
    ylabel="Vertimiento [MWh]", 
    title="Vertimiento de Renovables",
    legend=false, 
    size=(900,400),
    color=:red,
    yformatter=:scientific)
savefig(p2, "vertimiento.png")

# Gráfico de congestión
p3 = bar(df.caso, df.lineas_congestionadas, 
    xlabel="Caso", 
    ylabel="N° Congestiones", 
    title="Congestión de Líneas",
    legend=false, 
    size=(900,400),
    color=:orange)
savefig(p3, "congestion.png")

# Gráfico de demanda agregada
# Usar los datos del primer caso para la demanda
x = resultados[1]["horasDia"]
# Leer datos de demanda del archivo correspondiente
archivo_demanda = resultados[1]["nombre_caso"] == "Base" ? "Predespacho/UC_datEx8_sinER.xlsx" : "Predespacho/UC_datEx8.xlsx"
try
    local datDem = XLSX.readdata(archivo_demanda, "dem!A4:J27")
    # Convertir a matriz y reemplazar valores faltantes con 0
    datDem = replace(datDem, missing => 0.0)
    local y = vec(sum(datDem[:,2:end], dims=2))
    local p4 = plot(x, y, 
        xlabel="Hora", 
        ylabel="Demanda [MW]", 
        title="Demanda Agregada",
        label="Demanda",
        linewidth=2,
        color=:blue)
    savefig(p4, "Demanda.png")
catch e
    @warn "No se pudo generar el gráfico de demanda: $e"
end


# --- GUARDAR EN EXCEL ---
# Primero escribe la hoja resumen y crea el archivo
XLSX.writetable("Resultados_UC_Comparacion.xlsx", df; sheetname="Resumen", overwrite=true)

# Función para procesar datos renovables
function procesar_datos_renovables(r, sheet_erv, row)
    # Verificar si es el caso base
    if get(r, "nombre_caso", "") == "Base"
        return row
    end
    
    # Verificar si tenemos los datos necesarios
    if !haskey(r, "tipoGen") || !haskey(r, "pEr") || !haskey(r, "pg") || !haskey(r, "horasDia")
        return row
    end
    
    # Convertir datos a tipos seguros usando skipmissing
    tipoGen = collect(skipmissing(r["tipoGen"]))
    pEr = collect(skipmissing(r["pEr"]))
    pg = collect(skipmissing(r["pg"]))
    horas = collect(skipmissing(r["horasDia"]))
    
    # Verificar que los datos no estén vacíos
    if isempty(tipoGen) || isempty(pEr) || isempty(pg) || isempty(horas)
        return row
    end
    
    # Encontrar generadores renovables
    idx_renovables = findall(x -> x == 2, tipoGen)
    
    # Verificar que el número de generadores renovables coincida con las columnas de pEr
    if length(idx_renovables) != size(pEr, 2)
        @warn "Número de generadores renovables ($(length(idx_renovables))) no coincide con columnas de pEr ($(size(pEr, 2)))"
        return row
    end
    
    # Para cada generador renovable
    for (k, i) in enumerate(idx_renovables)
        try
            # Verificar que las dimensiones coincidan
            if size(pg, 1) < i || size(pg, 2) != length(horas)
                @warn "Dimensiones incorrectas para pg en generador $i: pg=$(size(pg)), horas=$(length(horas))"
                continue
            end
            
            # Asegurarse de que pEr tenga la forma correcta
            if size(pEr, 1) != length(horas)
                @warn "Dimensiones incorrectas para pEr en generador $i: pEr=$(size(pEr)), horas=$(length(horas))"
                continue
            end
            
            # Calcular totales usando skipmissing
            total_erv = sum(skipmissing(pEr[:,k]))
            total_pg = sum(skipmissing(pg[i,:]))
            total_vert = sum(skipmissing(max.(0, pEr[:,k] - pg[i,:])))
            pct_vert = total_erv > 0 ? (total_vert / total_erv * 100) : 0.0
            
            # Escribir datos hora por hora
            for h in 1:length(horas)
                sheet_erv["A"*string(row)] = r["nombre_caso"]
                sheet_erv["B"*string(row)] = "G"*string(i)
                sheet_erv["C"*string(row)] = horas[h]
                sheet_erv["D"*string(row)] = coalesce(pEr[h,k], 0.0)
                sheet_erv["E"*string(row)] = coalesce(pg[i,h], 0.0)
                sheet_erv["F"*string(row)] = max(0, coalesce(pEr[h,k], 0.0) - coalesce(pg[i,h], 0.0))
                row += 1
            end
            
            # Escribir totales
            sheet_erv["A"*string(row)] = r["nombre_caso"]
            sheet_erv["B"*string(row)] = "G"*string(i)
            sheet_erv["C"*string(row)] = "Total"
            sheet_erv["D"*string(row)] = total_erv
            sheet_erv["E"*string(row)] = total_pg
            sheet_erv["F"*string(row)] = total_vert
            row += 1
            
        catch e
            @warn "Error procesando generador $i en caso $(r["nombre_caso"]): $e"
            continue
        end
    end
    
    return row
end

# Luego abre el archivo y agrega las hojas de detalle
XLSX.openxlsx("Resultados_UC_Comparacion.xlsx", mode="rw") do xf
    # Crear hoja de resumen de ERV con un nombre único
    sheet_name = "Resumen_ERV_$(Dates.format(now(), "yyyymmdd_HHMMSS"))"
    sheet_erv = XLSX.addsheet!(xf, sheet_name)
    
    # Escribir encabezados
    sheet_erv["A1"] = "Caso"
    sheet_erv["B1"] = "Generador"
    sheet_erv["C1"] = "Hora"
    sheet_erv["D1"] = "Perfil ERV [MW]"
    sheet_erv["E1"] = "Generación Real [MW]"
    sheet_erv["F1"] = "Vertimiento [MW]"
    sheet_erv["G1"] = "Total ERV [MW]"
    sheet_erv["H1"] = "Total Generación [MW]"
    sheet_erv["I1"] = "Total Vertimiento [MW]"
    sheet_erv["J1"] = "% Vertimiento"
    
    # Contador de fila
    row = 2
    
    # Para cada caso
    for r in resultados
        try
            row = procesar_datos_renovables(r, sheet_erv, row)
        catch e
            @warn "Error procesando caso $(r["nombre_caso"]): $e"
            continue
        end
    end
    
    # Agregar formato
    # Formato de porcentaje para la columna J
    for i in 2:row-1
        if sheet_erv["C"*string(i)] == "TOTAL"
            sheet_erv["J"*string(i)] = "=I"*string(i)*"/G"*string(i)*"*100"
        end
    end
    
    # Continuar con las hojas de detalle existentes
    for r in resultados
        hoja = r["nombre_caso"]
        local pg = r["pg"]
        local ug = r["commitment"]
        local cmg = r["cmg"]
        local fTx = r["fTx"]
        
        # Convertir matrices a DataFrames con nombres de columnas
        df_pg = DataFrame(pg, ["t"*string(i) for i in 1:size(pg,2)])
        df_ug = DataFrame(ug, ["t"*string(i) for i in 1:size(ug,2)])
        df_cmg = DataFrame(cmg, ["t"*string(i) for i in 1:size(cmg,2)])
        df_fTx = DataFrame(fTx, ["t"*string(i) for i in 1:size(fTx,2)])
        
        # Crear hojas y escribir datos
        sheet_pg = XLSX.addsheet!(xf, hoja*"_pg")
        sheet_ug = XLSX.addsheet!(xf, hoja*"_ug")
        sheet_cmg = XLSX.addsheet!(xf, hoja*"_cmg")
        sheet_fTx = XLSX.addsheet!(xf, hoja*"_fTx")
        
        XLSX.writetable!(sheet_pg, df_pg)
        XLSX.writetable!(sheet_ug, df_ug)
        XLSX.writetable!(sheet_cmg, df_cmg)
        XLSX.writetable!(sheet_fTx, df_fTx)
    end
end

println("\n¡Análisis completado! Revisa los archivos de gráficos y Excel generados.") 