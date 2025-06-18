using JuMP
using HiGHS
using Plots
using DataFrames
using XLSX
using LinearAlgebra

# Estructura para almacenar resultados
struct ResultadosCaso
    costos_totales::Float64
    costos_marginales::Array{Float64,2}
    commitment::Array{Float64,2}
    flujos_lineas::Array{Float64,2}
    vertimiento_ER::Array{Float64,2}
    lineas_congestionadas::Array{Int64,1}
end

# Función para ejecutar un caso específico
function ejecutar_caso(tipo_caso::Int)
    # Configuración del caso
    TIPO_CASO_CON_SIN_ER = tipo_caso == 0 ? 0 : 1
    TIPO_SERIE_ERV = tipo_caso
    
    # Selección del archivo de datos
    NOMBRE_ARCHIVO_DATOS = TIPO_CASO_CON_SIN_ER == 0 ? "Predespacho/UC_datEx8_sinER.xlsx" : "Predespacho/UC_datEx8.xlsx"
    
    # Leer datos
    if TIPO_CASO_CON_SIN_ER == 0
        datGen = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "Gen!C4:O12")
        datDem = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "dem!A4:J27")
        datLineas = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "Lineas!A4:G14")
    else
        datGen = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "Gen!C4:O14")
        datDem = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "dem!A4:J27")
        datLineas = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "Lineas!A4:G14")
        
        # Leer datos de energía renovable según el perfil
        if TIPO_SERIE_ERV in [1,2,3]
            datEr = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "ERV!C$(5+8*(TIPO_SERIE_ERV-1)):AB$(6+8*(TIPO_SERIE_ERV-1))")
        elseif TIPO_SERIE_ERV in [4,5,6]
            datEr = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "ERV!C$(27+8*(TIPO_SERIE_ERV-4)):AB$(28+8*(TIPO_SERIE_ERV-4))")
        else
            datEr = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "ERV!C$(49+8*(TIPO_SERIE_ERV-7)):AB$(50+8*(TIPO_SERIE_ERV-7))")
        end
    end
    
    # Configurar parámetros del modelo
    busGen = datGen[:,1]
    cv = datGen[:,2]
    cEnc = datGen[:,3]
    cApa = datGen[:,4]
    pmax = datGen[:,5]
    pmin = datGen[:,6]
    t_up = datGen[:,7]
    t_do = datGen[:,8]
    R_up = datGen[:,9]
    R_do = datGen[:,10]
    tipoGen = datGen[:,11]
    aportaReserva = datGen[:,12]
    kReserva = datGen[:,13]
    
    pd = datDem[:,2:end]
    horasDia = datDem[:,1]
    Tmax = datLineas[:,5]
    xij = datLineas[:,4]
    fromTx = datLineas[:,2]
    toTx = datLineas[:,3]
    
    # Crear modelo
    m = Model(HiGHS.Optimizer)
    
    # Definir variables
    ng = length(cv)
    nTx = length(Tmax)
    nT = length(pd[:,1])
    nBus = maximum(datLineas[:,[2,3]])
    
    @variable(m, pg[1:ng,1:nT])
    @variable(m, rg[1:ng,1:nT])
    @variable(m, fTx[1:nTx,1:nT])
    @variable(m, theta[1:nBus,1:nT])
    @variable(m, ug[1:ng,1:nT], Bin)
    @variable(m, uEnc[1:ng,1:nT], Bin)
    @variable(m, uApa[1:ng,1:nT], Bin)
    
    # Función objetivo
    @objective(m, Min, sum(sum(cv[i]*pg[i,j] + cEnc[i]*uEnc[i,j] + cApa[i]*uApa[i,j] for i in 1:ng) for j in 1:nT))
    
    # Construir matrices para el modelo
    A = zeros(nBus,nTx)
    for k in 1:nTx
        A[toTx[k],k] = -1
        A[fromTx[k],k] = 1
    end
    
    Ag = zeros(nBus,ng)
    for k in 1:ng
        Ag[busGen[k],k] = 1
    end
    
    Ad = Matrix(Diagonal(ones(nBus)))
    Y = Matrix(Diagonal(1.0./xij))
    
    # Restricciones del modelo
    # Balance de potencia
    @constraint(m, balance[j in 1:nT], Ag*pg[:,j] - A*fTx[:,j] .== Ad*pd[j,:])
    
    # Restricción de flujo
    @constraint(m, flujoTx[j in 1:nT], fTx[:,j] .== Y*A'*theta[:,j])
    
    # Restricciones de límites de generación
    for i in 1:ng
        if tipoGen[i] == 2  # Generador renovable
            @constraint(m, [j in 1:nT], pg[i,j] + rg[i,j] <= pEr[j,i-ng+2]*ug[i,j])
            @constraint(m, [j in 1:nT], pg[i,j] >= pmin[i]*ug[i,j])
            @constraint(m, [j in 1:nT], rg[i,j] == 0)
        else  # Generador convencional
            @constraint(m, [j in 1:nT], pg[i,j] + rg[i,j] <= pmax[i]*ug[i,j])
            @constraint(m, [j in 1:nT], pg[i,j] >= pmin[i]*ug[i,j])
        end
    end
    
    # Límites de líneas de transmisión
    @constraint(m, [i in 1:nTx, j in 1:nT], fTx[i,j] <= Tmax[i])
    @constraint(m, [i in 1:nTx, j in 1:nT], fTx[i,j] >= -Tmax[i])
    
    # Restricciones de reserva
    for i in 1:ng
        if aportaReserva[i] == 1
            @constraint(m, [j in 1:nT], rg[i,j] >= kReserva[i]*pmax[i]*ug[i,j])
        end
    end
    
    # Restricciones de rampa
    @constraint(m, ramp_up[i in 1:ng, j in 2:nT], pg[i,j] - pg[i,j-1] + rg[i,j] <= R_up[i])
    @constraint(m, ramp_dw[i in 1:ng, j in 2:nT], pg[i,j] - pg[i,j-1] >= -R_do[i])
    
    # Restricciones de commitment
    @constraint(m, [i in 1:ng], ug[i,1] == uEnc[i,1] - uApa[i,1])
    @constraint(m, [i in 1:ng], ug[i,1] >= uEnc[i,1])
    @constraint(m, [i in 1:ng], 1-ug[i,1] >= uApa[i,1])
    
    @constraint(m, [i in 1:ng, j in 2:nT], ug[i,j] == ug[i,j-1] + uEnc[i,j] - uApa[i,j])
    
    # Tiempos mínimos de operación
    for i in 1:ng
        rang1 = t_up[i]:nT
        for j in rang1
            rang2 = (j-t_up[i]+1):j
            @constraint(m, ug[i,j] >= sum(uEnc[i,k] for k in rang2))
        end
    end
    
    @constraint(m, [i in 1:ng, j in 2:t_up[i]], ug[i,j] >= sum(uEnc[i,k] for k in 1:j))
    
    # Tiempos mínimos de apagado
    for i in 1:ng
        rang1 = t_do[i]:nT
        for j in rang1
            rang2 = (j-t_do[i]+1):j
            @constraint(m, 1-ug[i,j] >= sum(uApa[i,k] for k in rang2))
        end
    end
    
    @constraint(m, [i in 1:ng, j in 2:t_do[i]], 1-ug[i,j] >= sum(uApa[i,k] for k in 1:j))
    
    # Optimizar
    optimize!(m)
    
    # Calcular vertimiento de ER
    vertimiento = zeros(nT, 2)
    if TIPO_CASO_CON_SIN_ER == 1
        for j in 1:nT
            for i in 1:ng
                if tipoGen[i] == 2
                    vertimiento[j,i-ng+2] = max(0, pEr[j,i-ng+2] - value.(pg[i,j]))
                end
            end
        end
    end
    
    # Calcular costos marginales
    costos_marginales = zeros(nBus, nT)
    for j in 1:nT
        for b in 1:nBus
            costos_marginales[b,j] = dual(balance[j][b])
        end
    end
    
    # Recolectar resultados
    resultados = ResultadosCaso(
        objective_value(m),
        costos_marginales,
        value.(ug),
        value.(fTx),
        vertimiento,
        findall(abs.(value.(fTx)) .>= Tmax .- 1e-6)
    )
    
    return resultados
end

# Función para analizar y comparar resultados
function analizar_resultados(resultados::Array{ResultadosCaso,1})
    # Crear DataFrame para almacenar resultados comparativos
    df = DataFrame(
        Caso = ["Base", "Caso 1", "Caso 2", "Caso 3", "Caso 4", "Caso 5", "Caso 6", "Caso 7", "Caso 8", "Caso 9"],
        Costo_Total = [r.costos_totales for r in resultados],
        Lineas_Congestionadas = [length(r.lineas_congestionadas) for r in resultados]
    )
    
    # Generar gráficos comparativos
    p1 = plot(df.Caso, df.Costo_Total, 
        title="Comparación de Costos Totales",
        xlabel="Caso",
        ylabel="Costo Total",
        seriestype=:bar)
    
    p2 = plot(df.Caso, df.Lineas_Congestionadas,
        title="Número de Líneas Congestionadas",
        xlabel="Caso",
        ylabel="Número de Líneas",
        seriestype=:bar)
    
    # Guardar resultados
    savefig(p1, "comparacion_costos.png")
    savefig(p2, "comparacion_congestion.png")
    
    return df
end

# Función para analizar el vertimiento de ER
function analizar_vertimiento(resultados::Array{ResultadosCaso,1})
    df_vertimiento = DataFrame(
        Caso = ["Base", "Caso 1", "Caso 2", "Caso 3", "Caso 4", "Caso 5", "Caso 6", "Caso 7", "Caso 8", "Caso 9"],
        Vertimiento_Total = [sum(r.vertimiento_ER) for r in resultados],
        Max_Vertimiento = [maximum(r.vertimiento_ER) for r in resultados]
    )
    
    p = plot(df_vertimiento.Caso, df_vertimiento.Vertimiento_Total,
        title="Vertimiento Total de Energía Renovable",
        xlabel="Caso",
        ylabel="MWh",
        seriestype=:bar)
    
    savefig(p, "vertimiento_ER.png")
    return df_vertimiento
end

# Función para analizar los costos marginales
function analizar_costos_marginales(resultados::Array{ResultadosCaso,1})
    costos_promedio = [mean(r.costos_marginales) for r in resultados]
    costos_max = [maximum(r.costos_marginales) for r in resultados]
    
    df_cmg = DataFrame(
        Caso = ["Base", "Caso 1", "Caso 2", "Caso 3", "Caso 4", "Caso 5", "Caso 6", "Caso 7", "Caso 8", "Caso 9"],
        CMG_Promedio = costos_promedio,
        CMG_Max = costos_max
    )
    
    p1 = plot(df_cmg.Caso, df_cmg.CMG_Promedio,
        title="Costo Marginal Promedio",
        xlabel="Caso",
        ylabel="\$/MWh",
        seriestype=:bar)
    
    p2 = plot(df_cmg.Caso, df_cmg.CMG_Max,
        title="Costo Marginal Máximo",
        xlabel="Caso",
        ylabel="\$/MWh",
        seriestype=:bar)
    
    savefig(p1, "cmg_promedio.png")
    savefig(p2, "cmg_max.png")
    
    return df_cmg
end

# Función para generar reporte completo
function generar_reporte(resultados::Array{ResultadosCaso,1})
    # Análisis básico
    df_basico = analizar_resultados(resultados)
    
    # Análisis de vertimiento
    df_vertimiento = analizar_vertimiento(resultados)
    
    # Análisis de costos marginales
    df_cmg = analizar_costos_marginales(resultados)
    
    # Generar reporte en Excel
    XLSX.openxlsx("reporte_analisis.xlsx", mode="w") do xf
        XLSX.addsheet!(xf, "Resumen")
        XLSX.addsheet!(xf, "Vertimiento")
        XLSX.addsheet!(xf, "Costos_Marginales")
        
        # Escribir datos en las hojas
        XLSX.writetable!(xf["Resumen"], df_basico)
        XLSX.writetable!(xf["Vertimiento"], df_vertimiento)
        XLSX.writetable!(xf["Costos_Marginales"], df_cmg)
    end
    
    println("Reporte generado exitosamente en 'reporte_analisis.xlsx'")
end

# Ejecutar análisis completo
println("Iniciando análisis de casos...")
resultados = []
for caso in 0:9
    println("Ejecutando caso $caso...")
    push!(resultados, ejecutar_caso(caso))
end

println("Generando reporte completo...")
generar_reporte(resultados) 