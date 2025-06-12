using JuMP, HiGHS, XLSX, DataFrames, Plots, LinearAlgebra

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
        rangos = Dict(
            1 => "ERV!C5:AB6", 2 => "ERV!C13:AB14", 3 => "ERV!C20:AB21",
            4 => "ERV!C27:AB28", 5 => "ERV!C35:AB36", 6 => "ERV!C42:AB43",
            7 => "ERV!C49:AB50", 8 => "ERV!C56:AB57", 9 => "ERV!C63:AB64"
        )
        datEr = XLSX.readdata(archivo, rangos[tipo_serie])
        pEr = datEr[:,3:end]'
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
    nT  = length(pd[:,1])
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
        "busGen" => busGen
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
bar(df.caso, df.costo_total, xlabel="Caso", ylabel="Costo Total", title="Comparación de Costos Totales", legend=false, size=(900,400))
savefig("costos_totales.png")

bar(df.caso, df.vertimiento, xlabel="Caso", ylabel="Vertimiento [MWh]", title="Vertimiento de Renovables", legend=false, size=(900,400))
savefig("vertimiento.png")

bar(df.caso, df.lineas_congestionadas, xlabel="Caso", ylabel="N° Congestiones", title="Congestión de Líneas", legend=false, size=(900,400))
savefig("congestion.png")

# --- GRAFICOS ADICIONALES POR CASO ---
for r in resultados
    local pg = r["pg"]
    local horas = r["horasDia"]
    plot(horas, pg', xlabel="Hora", ylabel="Potencia [MW]", title="Despacho de Generadores - " * r["nombre_caso"], label=["G"*string(i) for i in 1:size(pg,1)])
    savefig("despacho_" * r["nombre_caso"] * ".png")
    local ug = r["commitment"]
    heatmap(horas, 1:size(ug,1), ug, xlabel="Hora", ylabel="Generador", title="Commitment - " * r["nombre_caso"], colorbar_title="Encendido")
    savefig("commitment_" * r["nombre_caso"] * ".png")
    local cmg = r["cmg"]
    plot(horas, cmg', xlabel="Hora", ylabel="CMg [USD/MWh]", title="Costos Marginales - " * r["nombre_caso"], label=["Barra "*string(i) for i in 1:size(cmg,1)])
    savefig("cmg_" * r["nombre_caso"] * ".png")
end

# --- GUARDAR EN EXCEL ---
# Primero escribe la hoja resumen y crea el archivo
XLSX.writetable("Resultados_UC_Comparacion.xlsx", df; sheetname="Resumen", overwrite=true)

# Luego abre el archivo y agrega las hojas de detalle
XLSX.openxlsx("Resultados_UC_Comparacion.xlsx", mode="rw") do xf
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