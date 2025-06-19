using JuMP
using HiGHS
using Plots
using DataFrames
using XLSX
using LinearAlgebra
using Statistics

# Importar el módulo con la función resolver_UC
include("fun_predesp.jl")
using .FunPredesp

# Función para obtener el nombre del caso
function obtener_nombre_caso(tipo_caso, tipo_serie)
    if tipo_caso == 0
        return "Caso sin Energía Renovable"
    else
        perfiles = ["WT1 y WT2 perfil 1", "WT1 y WT2 perfil 2", "WT1 y WT2 perfil 3",
                   "PV1 y PV2 perfil 1", "PV1 y PV2 perfil 2", "PV1 y PV2 perfil 3",
                   "PV1 y WT2 perfil 1", "PV1 y WT2 perfil 2", "PV1 y WT2 perfil 3"]
        return "Caso con Energía Renovable: " * perfiles[tipo_serie]
    end
end

# Función para ejecutar un caso específico
function ejecutar_caso(tipo_caso, tipo_solver, tipo_serie)
    println("\n" * "="^50)
    println("Iniciando nuevo caso:")
    println("tipo_caso = $tipo_caso")
    println("tipo_solver = $tipo_solver")
    println("tipo_serie = $tipo_serie")
    println("="^50)
    
    # Cambiar al directorio Predespacho para encontrar los archivos Excel
    original_dir = pwd()
    try
        cd("Predespacho")
        
        # Ejecutar el modelo usando la función encapsulada
        resultado = resolver_UC(tipo_caso, tipo_solver, tipo_serie)
        
        # Extraer resultados del diccionario
        result2 = Dict()
        result2["Pg"] = resultado["Pg"]
        result2["Rg"] = resultado["Rg"]
        result2["ug"] = resultado["ug"]
        result2["fij"] = resultado["fij"]
        result2["ct"] = resultado["ct"]
        result2["cmg"] = resultado["cmg"]
        
        # Extraer datos adicionales
        pEr = resultado["pEr"]
        datGen = resultado["datGen"]
        pd = resultado["pd"]
        horasDia = resultado["horasDia"]
        tipoGen = resultado["tipoGen"]
        busGen = resultado["busGen"]
        
        # Calcular dimensiones
        ng = size(result2["Pg"], 1)
        nT = size(result2["Pg"], 2)
        
        # Calcular vertimiento ANTES del bloque Excel para que esté disponible al retornar
        generacion_total = zeros(nT)
        for i in 1:ng
            generacion_total += result2["Pg"][i,:]
        end
        if tipo_caso == 1 && size(pEr,1) > 0 && size(pEr,2) >= 2
            generacion_total += pEr[:,1] + pEr[:,2]
        end
        
        # Calcular demanda total por hora y convertir a matriz 1xn
        demanda_total = reshape(sum(pd, dims=2), 1, :)
        
        # Calcular vertimiento
        vertimiento = reshape(generacion_total, 1, :) - demanda_total
        
        println("\nVerificando resultados del modelo:")
        println("Costo total: $(result2["ct"])")
        println("Dimensiones de Pg: $(size(result2["Pg"]))")
        if tipo_caso == 1 && size(pEr,1) > 0
            println("Dimensiones de pEr: $(size(pEr))")
            println("Primeras filas de pEr:")
            println(pEr[1:3,:])
        end
        
        # Mensajes de depuración adicionales
        println("\nVerificando datos de entrada:")
        println("Número de generadores (ng): $ng")
        println("Número de períodos (nT): $nT")
        println("Tipo de caso: $(tipo_caso == 0 ? "Sin ER" : "Con ER")")
        println("Tipo de serie: $tipo_serie")
        println("\nPrimeras filas de potencia generada:")
        println(result2["Pg"][1:3,1:3])
        println("\nPrimeras filas de costos marginales:")
        println(result2["cmg"][1:3,1:3])
        
        # Guardar resultados con nombre específico
        nombre_archivo = "resultados_caso_$(tipo_caso)_$(tipo_solver)_$(tipo_serie).xlsx"
        println("\nGuardando resultados en: $nombre_archivo")
        
        # Crear un nuevo archivo Excel para los resultados
        XLSX.openxlsx(nombre_archivo, mode="w") do xf
            # Crear las hojas necesarias
            XLSX.addsheet!(xf, "Resultados")
            XLSX.addsheet!(xf, "Potencia_Generada")
            XLSX.addsheet!(xf, "Reserva")
            XLSX.addsheet!(xf, "Flujos")
            XLSX.addsheet!(xf, "Encendido")
            XLSX.addsheet!(xf, "Costos_Marginales")
            XLSX.addsheet!(xf, "Vertimiento")
            
            # Guardar resultados de potencia generada
            sheet = xf["Potencia_Generada"]
            sheet["A1"] = "Resultados de Potencia Generada"
            sheet["A3"] = "Central"
            sheet["B3"] = "Tipo"
            
            # Agregar nombres de centrales y tipos
            for i in 1:ng
                sheet["A$(i+3)"] = "Central $i"
                if tipoGen[i] == 1
                    sheet["B$(i+3)"] = "Térmica"
                elseif tipoGen[i] == 2
                    sheet["B$(i+3)"] = "Renovable"
                end
            end
            
            # Guardar potencias generadas - CORREGIDO: usar collect() para matrices transpuestas
            sheet["C4"] = collect(result2["Pg"])
            
            # Si es caso con renovables, agregar potencias renovables en filas 13 y 14
            if tipo_caso == 1 && size(pEr,1) > 0 && size(pEr,2) >= 2
                sheet["A13"] = "WT1"
                sheet["B13"] = "Eólica"
                sheet["A14"] = "WT2"
                sheet["B14"] = "Eólica"
                sheet["C13"] = collect(pEr[:,1])
                sheet["C14"] = collect(pEr[:,2])
            end
            
            # Guardar resultados de reserva - CORREGIDO: usar collect()
            sheet = xf["Reserva"]
            sheet["A1"] = "Resultados de Reserva"
            sheet["C4"] = collect(result2["Rg"])
            
            # Guardar resultados de flujos - CORREGIDO: usar collect()
            sheet = xf["Flujos"]
            sheet["A1"] = "Resultados de Flujos"
            sheet["E4"] = collect(result2["fij"])
            
            # Guardar resultados de encendido - CORREGIDO: usar collect()
            sheet = xf["Encendido"]
            sheet["A1"] = "Resultados de Encendido"
            sheet["C4"] = collect(result2["ug"])
            
            # Guardar resultados de costos marginales - CORREGIDO: usar collect()
            sheet = xf["Costos_Marginales"]
            sheet["A1"] = "Resultados de Costos Marginales"
            sheet["C4"] = collect(result2["cmg"])
            
            # Guardar resultados de vertimiento (ya calculado arriba)
            sheet = xf["Vertimiento"]
            sheet["A1"] = "Análisis de Vertimiento"
            sheet["A3"] = "Concepto"
            
            # Guardar resultados en la hoja de vertimiento - CORREGIDO: usar collect()
            sheet["A4"] = "Generación Total"
            sheet["A5"] = "Demanda Total"
            sheet["A6"] = "Vertimiento"
            sheet["C4"] = collect(reshape(generacion_total, 1, :))
            sheet["C5"] = collect(demanda_total)
            sheet["C6"] = collect(vertimiento)
            
            # Calcular ingresos y egresos por central
            cv = datGen[:,2]  # Costos variables de las centrales
            ingresos = zeros(ng, nT)
            egresos = zeros(ng, nT)
            for i in 1:ng
                for t in 1:nT
                    ingresos[i,t] = result2["cmg"][busGen[i],t] * result2["Pg"][i,t]
                    egresos[i,t] = cv[i] * result2["Pg"][i,t]
                end
            end
            
            # Si es caso con renovables, calcular ingresos de las renovables
            if tipo_caso == 1 && size(pEr,1) > 0 && size(pEr,2) >= 2
                # Encontrar las barras donde están conectadas las renovables
                indices_renovables = findall(x -> x == 2, tipoGen)
                if length(indices_renovables) >= 2
                    barra_wt1 = busGen[indices_renovables[1]]
                    barra_wt2 = busGen[indices_renovables[2]]
                    
                    # Calcular ingresos de las renovables
                    ingresos_wt1 = zeros(nT)
                    ingresos_wt2 = zeros(nT)
                    for t in 1:nT
                        ingresos_wt1[t] = result2["cmg"][barra_wt1,t] * pEr[t,1]
                        ingresos_wt2[t] = result2["cmg"][barra_wt2,t] * pEr[t,2]
                    end
                else
                    println("Advertencia: No se encontraron suficientes centrales renovables")
                    ingresos_wt1 = zeros(nT)
                    ingresos_wt2 = zeros(nT)
                end
            else
                ingresos_wt1 = zeros(nT)
                ingresos_wt2 = zeros(nT)
            end
            
            # Guardar resumen en la hoja de Resultados
            sheet = xf["Resultados"]
            nombre_caso = obtener_nombre_caso(tipo_caso, tipo_serie)
            println("\nGuardando resultados para: $nombre_caso")
            sheet["A1"] = nombre_caso
            sheet["A2"] = "Costo Total"
            sheet["B2"] = result2["ct"]
            
            # Copiar información de vertimiento - CORREGIDO: usar collect()
            sheet["A4"] = "Análisis de Vertimiento"
            sheet["A5"] = "Generación Total"
            sheet["A6"] = "Demanda Total"
            sheet["A7"] = "Vertimiento"
            sheet["C5"] = collect(reshape(generacion_total, 1, :))
            sheet["C6"] = collect(demanda_total)
            sheet["C7"] = collect(vertimiento)
            
            # Agregar ingresos y egresos por central
            sheet["A9"] = "Análisis Económico por Central"
            sheet["A10"] = "Central"
            sheet["B10"] = "Tipo"
            sheet["C10"] = "Ingresos Totales"
            sheet["D10"] = "Egresos Totales"
            sheet["E10"] = "Beneficio Total"
            
            # Agregar información de todas las centrales
            fila_actual = 11
            for i in 1:ng
                sheet["A$(fila_actual)"] = "Central $i"
                if tipoGen[i] == 1
                    sheet["B$(fila_actual)"] = "Térmica"
                    sheet["C$(fila_actual)"] = sum(ingresos[i,:])
                    sheet["D$(fila_actual)"] = sum(egresos[i,:])
                    sheet["E$(fila_actual)"] = sum(ingresos[i,:]) - sum(egresos[i,:])
                elseif tipoGen[i] == 2
                    sheet["B$(fila_actual)"] = "Renovable"
                    sheet["C$(fila_actual)"] = sum(ingresos[i,:])
                    sheet["D$(fila_actual)"] = 0  # No hay costos variables
                    sheet["E$(fila_actual)"] = sum(ingresos[i,:])
                end
                fila_actual += 1
            end
            
            # Agregar totales
            sheet["A$(fila_actual)"] = "TOTAL"
            if tipo_caso == 1 && size(pEr,1) > 0 && size(pEr,2) >= 2
                sheet["C$(fila_actual)"] = sum(ingresos) + sum(ingresos_wt1) + sum(ingresos_wt2)
                sheet["D$(fila_actual)"] = sum(egresos)
                sheet["E$(fila_actual)"] = sum(ingresos) + sum(ingresos_wt1) + sum(ingresos_wt2) - sum(egresos)
            else
                sheet["C$(fila_actual)"] = sum(ingresos)
                sheet["D$(fila_actual)"] = sum(egresos)
                sheet["E$(fila_actual)"] = sum(ingresos) - sum(egresos)
            end
            
            println("Resultados guardados exitosamente en $nombre_archivo")
        end
        
        # Retornar resultados para el reporte comparativo
        return (result2["ct"], result2["Pg"], result2["Rg"], result2["ug"], result2["fij"], result2["cmg"], vertimiento, datGen, pEr, tipo_caso)
        
    catch e
        println("Error al ejecutar el caso: ", e)
        if tipo_caso == 0
            println("Este error es esperado para el caso sin energía renovable")
        else
            println("Este error no es esperado para el caso con energía renovable")
        end
        return nothing
    finally
        # Regresar al directorio original
        cd(original_dir)
    end
end

# Función principal para ejecutar todos los casos
function ejecutar_todos_los_casos()
    println("🚀 INICIANDO ANÁLISIS COMPLETO DE CASOS")
    println("="^60)
    
    resultados = Dict()
    
    # Caso base (sin energía renovable)
    println("\n📊 EJECUTANDO CASO BASE")
    resultado_base = ejecutar_caso(0, 1, 1)
    if resultado_base !== nothing
        resultados["Base"] = resultado_base
    end
    
    # Casos con energía renovable
    println("\n🌱 EJECUTANDO CASOS CON ENERGÍA RENOVABLE")
    for tipo_serie in 1:9
        println("\n📈 Ejecutando perfil $tipo_serie...")
        resultado = ejecutar_caso(1, 1, tipo_serie)
        if resultado !== nothing
            resultados["Caso_$tipo_serie"] = resultado
        end
    end
    
    # Generar reporte comparativo
    println("\n📋 GENERANDO REPORTE COMPARATIVO")
    generar_reporte_comparativo(resultados)
    
    println("\n✅ ANÁLISIS COMPLETO FINALIZADO")
    return resultados
end

# Función para generar reporte comparativo
function generar_reporte_comparativo(resultados)
    # Verificar si hay resultados exitosos
    if isempty(resultados)
        println("⚠️  No hay resultados exitosos para generar el reporte comparativo")
        println("   Verifique que los archivos Excel estén disponibles y el modelo funcione correctamente")
        return nothing
    end
    
    # Crear DataFrame con resumen detallado
    casos = []
    costos = []
    potencias_generadas = []
    vertimientos_totales = []
    ingresos_totales = []
    egresos_totales = []
    beneficios_totales = []
    
    for (nombre, resultado) in resultados
        push!(casos, nombre)
        push!(costos, resultado[1])  # resultado[1] es el costo total
        
        # Calcular potencia generada total
        pg_sol = resultado[2]
        potencia_total = sum(pg_sol)
        push!(potencias_generadas, potencia_total)
        
        # Calcular vertimiento total
        vertimiento = resultado[7]
        vertimiento_total = sum(vertimiento)
        push!(vertimientos_totales, vertimiento_total)
        
        # Calcular ingresos y egresos usando la lógica exacta de run_cases.jl
        pg_sol = resultado[2]
        costos_marginales = resultado[6]
        datGen = resultado[8]
        pEr = resultado[9]
        TIPO_CASO_CON_SIN_ER = resultado[10]
        
        cv = datGen[:,2]  # Costos variables de las centrales
        busGen = datGen[:,1]  # Barras donde están conectadas las centrales
        tipoGen = datGen[:,11]  # Tipo de generador
        ng = length(cv)
        nT = size(pg_sol, 2)
        
        # Calcular ingresos y egresos por central (igual que en run_cases.jl)
        ingresos = zeros(ng, nT)
        egresos = zeros(ng, nT)
        for i in 1:ng
            for t in 1:nT
                ingresos[i,t] = costos_marginales[busGen[i],t] * pg_sol[i,t]
                egresos[i,t] = cv[i] * pg_sol[i,t]
            end
        end
        
        # Si es caso con renovables, calcular ingresos de las renovables
        if TIPO_CASO_CON_SIN_ER == 1 && size(pEr,1) > 0 && size(pEr,2) >= 2
            # Encontrar las barras donde están conectadas las renovables
            indices_renovables = findall(x -> x == 2, tipoGen)
            if length(indices_renovables) >= 2
                barra_wt1 = busGen[indices_renovables[1]]
                barra_wt2 = busGen[indices_renovables[2]]
                
                # Calcular ingresos de las renovables
                ingresos_wt1 = zeros(nT)
                ingresos_wt2 = zeros(nT)
                for t in 1:nT
                    ingresos_wt1[t] = costos_marginales[barra_wt1,t] * pEr[t,1]
                    ingresos_wt2[t] = costos_marginales[barra_wt2,t] * pEr[t,2]
                end
            else
                ingresos_wt1 = zeros(nT)
                ingresos_wt2 = zeros(nT)
            end
        else
            ingresos_wt1 = zeros(nT)
            ingresos_wt2 = zeros(nT)
        end
        
        # Calcular totales (igual que en run_cases.jl)
        if TIPO_CASO_CON_SIN_ER == 1 && size(pEr,1) > 0 && size(pEr,2) >= 2
            ingresos_aprox = sum(ingresos) + sum(ingresos_wt1) + sum(ingresos_wt2)
        else
            ingresos_aprox = sum(ingresos)
        end
        egresos_aprox = sum(egresos)
        beneficio_aprox = ingresos_aprox - egresos_aprox
        
        push!(ingresos_totales, ingresos_aprox)
        push!(egresos_totales, egresos_aprox)
        push!(beneficios_totales, beneficio_aprox)
    end
    
    df = DataFrame(
        Caso = casos,
        Costo_Total = costos,
        Potencia_Generada_MWh = potencias_generadas,
        Vertimiento_Total_MWh = vertimientos_totales,
        Ingresos_Totales = ingresos_totales,
        Egresos_Totales = egresos_totales,
        Beneficio_Total = beneficios_totales
    )
    
    # Guardar reporte comparativo detallado
    XLSX.openxlsx("reporte_comparativo_casos.xlsx", mode="w") do xf
        XLSX.addsheet!(xf, "Comparacion_General")
        XLSX.writetable!(xf["Comparacion_General"], df)
        
        # Agregar hoja con detalles por caso
        XLSX.addsheet!(xf, "Detalles_Por_Caso")
        sheet = xf["Detalles_Por_Caso"]
        
        # Encabezados
        sheet["A1"] = "Análisis Detallado por Caso"
        sheet["A3"] = "Caso"
        sheet["B3"] = "Costo Total (\$)"
        sheet["C3"] = "Potencia Generada (MWh)"
        sheet["D3"] = "Vertimiento Total (MWh)"
        sheet["E3"] = "Ingresos Totales (\$)"
        sheet["F3"] = "Egresos Totales (\$)"
        sheet["G3"] = "Beneficio Total (\$)"
        sheet["H3"] = "Reducción de Costos vs Base (%)"
        
        # Datos
        costo_base = resultados["Base"][1]
        for (i, (nombre, resultado)) in enumerate(resultados)
            fila = i + 3
            sheet["A$fila"] = nombre
            sheet["B$fila"] = resultado[1]
            sheet["C$fila"] = sum(resultado[2])
            sheet["D$fila"] = sum(resultado[7])
            sheet["E$fila"] = ingresos_totales[i]
            sheet["F$fila"] = egresos_totales[i]
            sheet["G$fila"] = beneficios_totales[i]
            
            # Calcular reducción de costos vs caso base
            if nombre != "Base"
                reduccion = ((costo_base - resultado[1]) / costo_base) * 100
                sheet["H$fila"] = reduccion
            else
                sheet["H$fila"] = 0.0
            end
        end
        
        # Agregar hoja con análisis de vertimiento por hora
        XLSX.addsheet!(xf, "Vertimiento_Por_Hora")
        sheet = xf["Vertimiento_Por_Hora"]
        sheet["A1"] = "Vertimiento de Energía Renovable por Hora"
        sheet["A3"] = "Hora"
        
        # Encabezados de casos
        for (i, (nombre, _)) in enumerate(resultados)
            col = Char(Int('B') + i - 1)
            sheet["$(col)3"] = nombre
        end
        
        # Datos por hora (asumiendo 24 horas)
        for hora in 1:24
            fila = hora + 3
            sheet["A$fila"] = hora
            
            for (i, (nombre, resultado)) in enumerate(resultados)
                col = Char(Int('B') + i - 1)
                vertimiento = resultado[7]
                if length(vertimiento) >= hora
                    sheet["$(col)$fila"] = vertimiento[hora]
                else
                    sheet["$(col)$fila"] = 0.0
                end
            end
        end
        
        # Agregar hoja con potencia generada por hora
        XLSX.addsheet!(xf, "Potencia_Por_Hora")
        sheet = xf["Potencia_Por_Hora"]
        sheet["A1"] = "Potencia Generada por Hora"
        sheet["A3"] = "Hora"
        
        # Encabezados de casos
        for (i, (nombre, _)) in enumerate(resultados)
            col = Char(Int('B') + i - 1)
            sheet["$(col)3"] = nombre
        end
        
        # Datos por hora
        for hora in 1:24
            fila = hora + 3
            sheet["A$fila"] = hora
            
            for (i, (nombre, resultado)) in enumerate(resultados)
                col = Char(Int('B') + i - 1)
                pg_sol = resultado[2]
                if size(pg_sol, 2) >= hora
                    potencia_total_hora = sum(pg_sol[:, hora])
                    sheet["$(col)$fila"] = potencia_total_hora
                else
                    sheet["$(col)$fila"] = 0.0
                end
            end
        end
        
        # Agregar hoja con costos marginales por hora
        XLSX.addsheet!(xf, "Costos_Marginales_Por_Hora")
        sheet = xf["Costos_Marginales_Por_Hora"]
        sheet["A1"] = "Costos Marginales por Hora"
        sheet["A3"] = "Hora"
        
        # Encabezados de casos
        for (i, (nombre, _)) in enumerate(resultados)
            col = Char(Int('B') + i - 1)
            sheet["$(col)3"] = nombre
        end
        
        # Datos por hora
        for hora in 1:24
            fila = hora + 3
            sheet["A$fila"] = hora
            
            for (i, (nombre, resultado)) in enumerate(resultados)
                col = Char(Int('B') + i - 1)
                costos_marginales = resultado[6]
                if size(costos_marginales, 2) >= hora
                    costo_marginal_promedio_hora = sum(costos_marginales[:, hora]) / size(costos_marginales, 1)
                    sheet["$(col)$fila"] = costo_marginal_promedio_hora
                else
                    sheet["$(col)$fila"] = 0.0
                end
            end
        end
        
        # Agregar hoja con análisis de vertimiento resumido
        XLSX.addsheet!(xf, "Analisis_Vertimiento")
        sheet = xf["Analisis_Vertimiento"]
        sheet["A1"] = "Análisis de Vertimiento de Energía Renovable"
        sheet["A3"] = "Caso"
        sheet["B3"] = "Vertimiento Total (MWh)"
        sheet["C3"] = "Vertimiento Máximo por Hora (MW)"
        sheet["D3"] = "Horas con Vertimiento"
        sheet["E3"] = "Horas sin Vertimiento"
        
        for (i, (nombre, resultado)) in enumerate(resultados)
            fila = i + 3
            vertimiento = resultado[7]
            vertimiento_total = sum(vertimiento)
            vertimiento_maximo = maximum(vertimiento)
            horas_con_vertimiento = count(x -> x > 0, vertimiento)
            horas_sin_vertimiento = length(vertimiento) - horas_con_vertimiento
            
            sheet["A$fila"] = nombre
            sheet["B$fila"] = vertimiento_total
            sheet["C$fila"] = vertimiento_maximo
            sheet["D$fila"] = horas_con_vertimiento
            sheet["E$fila"] = horas_sin_vertimiento
        end
        
        # Agregar hoja con análisis del commitment (estado de encendido/apagado)
        XLSX.addsheet!(xf, "Analisis_Commitment")
        sheet = xf["Analisis_Commitment"]
        sheet["A1"] = "Análisis del Commitment de Unidades"
        sheet["A3"] = "Caso"
        sheet["B3"] = "Central"
        sheet["C3"] = "Tipo"
        sheet["D3"] = "Horas Encendida"
        sheet["E3"] = "Horas Apagada"
        sheet["F3"] = "Factor de Utilización (%)"
        sheet["G3"] = "Horas de Arranque"
        sheet["H3"] = "Horas de Parada"
        
        fila_actual = 4
        for (nombre, resultado) in resultados
            ug_sol = resultado[4]  # Estado de encendido
            datGen = resultado[8]
            tipoGen = datGen[:,11]
            ng = size(ug_sol, 1)
            nT = size(ug_sol, 2)
            
            # Calcular estadísticas de commitment para cada central
            for i in 1:ng
                horas_encendida = sum(ug_sol[i,:])
                horas_apagada = nT - horas_encendida
                factor_utilizacion = (horas_encendida / nT) * 100
                
                # Calcular número de arranques y paradas
                arranques = 0
                paradas = 0
                for t in 2:nT
                    if ug_sol[i,t] > 0.5 && ug_sol[i,t-1] < 0.5  # Arranque
                        arranques += 1
                    elseif ug_sol[i,t] < 0.5 && ug_sol[i,t-1] > 0.5  # Parada
                        paradas += 1
                    end
                end
                
                sheet["A$fila_actual"] = nombre
                sheet["B$fila_actual"] = "Central $i"
                if tipoGen[i] == 1
                    sheet["C$fila_actual"] = "Térmica"
                elseif tipoGen[i] == 2
                    sheet["C$fila_actual"] = "Renovable"
                end
                sheet["D$fila_actual"] = horas_encendida
                sheet["E$fila_actual"] = horas_apagada
                sheet["F$fila_actual"] = round(factor_utilizacion, digits=2)
                sheet["G$fila_actual"] = arranques
                sheet["H$fila_actual"] = paradas
                
                fila_actual += 1
            end
        end
        
        # Agregar hoja con commitment por hora
        XLSX.addsheet!(xf, "Commitment_Por_Hora")
        sheet = xf["Commitment_Por_Hora"]
        sheet["A1"] = "Estado de Commitment por Hora"
        sheet["A3"] = "Hora"
        
        # Encabezados de casos
        for (i, (nombre, _)) in enumerate(resultados)
            col = Char(Int('B') + i - 1)
            sheet["$(col)3"] = nombre
        end
        
        # Datos por hora - número total de unidades encendidas
        for hora in 1:24
            fila = hora + 3
            sheet["A$fila"] = hora
            
            for (i, (nombre, resultado)) in enumerate(resultados)
                col = Char(Int('B') + i - 1)
                ug_sol = resultado[4]
                if size(ug_sol, 2) >= hora
                    unidades_encendidas = sum(ug_sol[:, hora])
                    sheet["$(col)$fila"] = unidades_encendidas
                else
                    sheet["$(col)$fila"] = 0.0
                end
            end
        end
        
        # Agregar hoja con análisis de líneas congestionadas
        XLSX.addsheet!(xf, "Analisis_Líneas_Congestionadas")
        sheet = xf["Analisis_Líneas_Congestionadas"]
        sheet["A1"] = "Análisis de Líneas Congestionadas"
        sheet["A3"] = "Caso"
        sheet["B3"] = "Línea"
        sheet["C3"] = "Desde"
        sheet["D3"] = "Hasta"
        sheet["E3"] = "Capacidad Máxima (MW)"
        sheet["F3"] = "Flujo Máximo (MW)"
        sheet["G3"] = "Factor de Carga (%)"
        sheet["H3"] = "Horas Congestionada"
        sheet["I3"] = "Horas al Límite (>95%)"
        
        fila_actual = 4
        for (nombre, resultado) in resultados
            fij_sol = resultado[5]  # Flujos en líneas
            
            # Cambiar al directorio Predespacho para leer los datos de líneas
            original_dir = pwd()
            datLineas = nothing
            try
                cd("Predespacho")
                datLineas = XLSX.readdata("UC_datEx8.xlsx", "Lineas!A4:G14")
                if datLineas === nothing || isempty(datLineas)
                    error("No se pudieron leer los datos de líneas del archivo UC_datEx8.xlsx")
                end
            catch e
                println("Error al leer datos de líneas: ", e)
                # Intentar con el archivo sin ER si el principal falla
                try
                    datLineas = XLSX.readdata("UC_datEx8_sinER.xlsx", "Lineas!A4:G14")
                catch e2
                    println("Error al leer datos de líneas del archivo sin ER: ", e2)
                    error("No se pudieron leer los datos de líneas de ningún archivo")
                end
            finally
                cd(original_dir)
            end
            
            Tmax = datLineas[:,5]  # Capacidad máxima
            fromTx = datLineas[:,2]  # Barra origen
            toTx = datLineas[:,3]    # Barra destino
            nTx = length(Tmax)
            nT = size(fij_sol, 2)
            
            # Analizar cada línea
            for i in 1:nTx
                flujo_maximo = maximum(abs.(fij_sol[i,:]))
                factor_carga = (flujo_maximo / Tmax[i]) * 100
                horas_congestionada = count(t -> abs(fij_sol[i,t]) >= Tmax[i] * 0.99, 1:nT)
                horas_al_limite = count(t -> abs(fij_sol[i,t]) >= Tmax[i] * 0.95, 1:nT)
                
                sheet["A$fila_actual"] = nombre
                sheet["B$fila_actual"] = "Línea $i"
                sheet["C$fila_actual"] = fromTx[i]
                sheet["D$fila_actual"] = toTx[i]
                sheet["E$fila_actual"] = Tmax[i]
                sheet["F$fila_actual"] = round(flujo_maximo, digits=2)
                sheet["G$fila_actual"] = round(factor_carga, digits=2)
                sheet["H$fila_actual"] = horas_congestionada
                sheet["I$fila_actual"] = horas_al_limite
                
                fila_actual += 1
            end
        end
        
        # Agregar hoja con flujos por hora
        XLSX.addsheet!(xf, "Flujos_Por_Hora")
        sheet = xf["Flujos_Por_Hora"]
        sheet["A1"] = "Flujos en Líneas por Hora"
        sheet["A3"] = "Hora"
        
        # Encabezados de casos
        for (i, (nombre, _)) in enumerate(resultados)
            col = Char(Int('B') + i - 1)
            sheet["$(col)3"] = nombre
        end
        
        # Datos por hora - flujo total en el sistema
        for hora in 1:24
            fila = hora + 3
            sheet["A$fila"] = hora
            
            for (i, (nombre, resultado)) in enumerate(resultados)
                col = Char(Int('B') + i - 1)
                fij_sol = resultado[5]
                if size(fij_sol, 2) >= hora
                    flujo_total = sum(abs.(fij_sol[:, hora]))
                    sheet["$(col)$fila"] = round(flujo_total, digits=2)
                else
                    sheet["$(col)$fila"] = 0.0
                end
            end
        end
        
        # Agregar hoja con resumen de congestión por caso
        XLSX.addsheet!(xf, "Resumen_Congestion")
        sheet = xf["Resumen_Congestion"]
        sheet["A1"] = "Resumen de Congestión por Caso"
        sheet["A3"] = "Caso"
        sheet["B3"] = "Líneas Congestionadas"
        sheet["C3"] = "Líneas al Límite (>95%)"
        sheet["D3"] = "Total de Líneas"
        sheet["E3"] = "Factor de Congestión (%)"
        sheet["F3"] = "Flujo Promedio (MW)"
        sheet["G3"] = "Flujo Máximo (MW)"
        
        for (i, (nombre, resultado)) in enumerate(resultados)
            fila = i + 3
            fij_sol = resultado[5]
            
            # Cambiar al directorio Predespacho para leer los datos de líneas
            original_dir = pwd()
            datLineas = nothing
            try
                cd("Predespacho")
                datLineas = XLSX.readdata("UC_datEx8.xlsx", "Lineas!A4:G14")
                if datLineas === nothing || isempty(datLineas)
                    error("No se pudieron leer los datos de líneas del archivo UC_datEx8.xlsx")
                end
            catch e
                println("Error al leer datos de líneas: ", e)
                # Intentar con el archivo sin ER si el principal falla
                try
                    datLineas = XLSX.readdata("UC_datEx8_sinER.xlsx", "Lineas!A4:G14")
                catch e2
                    println("Error al leer datos de líneas del archivo sin ER: ", e2)
                    error("No se pudieron leer los datos de líneas de ningún archivo")
                end
            finally
                cd(original_dir)
            end
            
            Tmax = datLineas[:,5]
            nTx = length(Tmax)
            nT = size(fij_sol, 2)
            
            # Calcular estadísticas de congestión
            lineas_congestionadas = 0
            lineas_al_limite = 0
            flujo_promedio = 0
            flujo_maximo = 0
            
            for j in 1:nTx
                flujo_max_linea = maximum(abs.(fij_sol[j,:]))
                flujo_prom_linea = mean(abs.(fij_sol[j,:]))
                
                if flujo_max_linea >= Tmax[j] * 0.99
                    lineas_congestionadas += 1
                end
                if flujo_max_linea >= Tmax[j] * 0.95
                    lineas_al_limite += 1
                end
                
                flujo_promedio += flujo_prom_linea
                flujo_maximo = max(flujo_maximo, flujo_max_linea)
            end
            
            flujo_promedio /= nTx
            factor_congestion = (lineas_congestionadas / nTx) * 100
            
            sheet["A$fila"] = nombre
            sheet["B$fila"] = lineas_congestionadas
            sheet["C$fila"] = lineas_al_limite
            sheet["D$fila"] = nTx
            sheet["E$fila"] = round(factor_congestion, digits=2)
            sheet["F$fila"] = round(flujo_promedio, digits=2)
            sheet["G$fila"] = round(flujo_maximo, digits=2)
        end
    end
    
    println("📊 Reporte comparativo detallado guardado en 'reporte_comparativo_casos.xlsx'")
    println("   - Comparacion_General: Resumen de todos los casos")
    println("   - Detalles_Por_Caso: Análisis detallado por caso")
    println("   - Vertimiento_Por_Hora: Vertimiento detallado por hora")
    println("   - Potencia_Por_Hora: Potencia generada detallada por hora")
    println("   - Costos_Marginales_Por_Hora: Costos marginales por hora")
    println("   - Analisis_Vertimiento: Resumen de vertimiento")
    println("   - Analisis_Commitment: Análisis del commitment de unidades")
    println("   - Commitment_Por_Hora: Estado de commitment por hora")
    println("   - Analisis_Líneas_Congestionadas: Análisis detallado de líneas")
    println("   - Flujos_Por_Hora: Flujos en líneas por hora")
    println("   - Resumen_Congestion: Resumen de congestión por caso")
    
    # Crear gráficos comparativos
    p1 = plot(df.Caso, df.Costo_Total, 
        title="Comparación de Costos Totales por Caso",
        xlabel="Caso",
        ylabel="Costo Total (\$)",
        seriestype=:bar,
        legend=false)
    
    p2 = plot(df.Caso, df.Vertimiento_Total_MWh,
        title="Vertimiento Total de Energía Renovable",
        xlabel="Caso",
        ylabel="Vertimiento (MWh)",
        seriestype=:bar,
        legend=false)
    
    p3 = plot(df.Caso, df.Beneficio_Total,
        title="Beneficio Total por Caso",
        xlabel="Caso",
        ylabel="Beneficio (\$)",
        seriestype=:bar,
        legend=false)
    
    savefig(p1, "comparacion_costos_casos.png")
    savefig(p2, "comparacion_vertimiento_casos.png")
    savefig(p3, "comparacion_beneficios_casos.png")
    
    # Crear gráficos adicionales para commitment y congestión
    # Gráfico de factor de utilización promedio por caso
    if haskey(resultados, "Base")
        casos_commitment = []
        factor_utilizacion_promedio = []
        
        for (nombre, resultado) in resultados
            ug_sol = resultado[4]
            ng = size(ug_sol, 1)
            nT = size(ug_sol, 2)
            
            # Calcular factor de utilización promedio de todas las unidades
            factor_total = 0
            for i in 1:ng
                horas_encendida = sum(ug_sol[i,:])
                factor_total += (horas_encendida / nT) * 100
            end
            factor_promedio = factor_total / ng
            
            push!(casos_commitment, nombre)
            push!(factor_utilizacion_promedio, factor_promedio)
        end
        
        p4 = plot(casos_commitment, factor_utilizacion_promedio,
            title="Factor de Utilización Promedio por Caso",
            xlabel="Caso",
            ylabel="Factor de Utilización (%)",
            seriestype=:bar,
            legend=false)
        savefig(p4, "factor_utilizacion_casos.png")
        
        # Gráfico de líneas congestionadas por caso
        casos_congestion = []
        lineas_congestionadas = []
        
        for (nombre, resultado) in resultados
            fij_sol = resultado[5]
            
            # Cambiar al directorio Predespacho para leer los datos de líneas
            original_dir = pwd()
            datLineas = nothing
            try
                cd("Predespacho")
                datLineas = XLSX.readdata("UC_datEx8.xlsx", "Lineas!A4:G14")
                if datLineas === nothing || isempty(datLineas)
                    error("No se pudieron leer los datos de líneas del archivo UC_datEx8.xlsx")
                end
            catch e
                println("Error al leer datos de líneas: ", e)
                # Intentar con el archivo sin ER si el principal falla
                try
                    datLineas = XLSX.readdata("UC_datEx8_sinER.xlsx", "Lineas!A4:G14")
                catch e2
                    println("Error al leer datos de líneas del archivo sin ER: ", e2)
                    error("No se pudieron leer los datos de líneas de ningún archivo")
                end
            finally
                cd(original_dir)
            end
            
            Tmax = datLineas[:,5]
            nTx = length(Tmax)
            nT = size(fij_sol, 2)
            
            # Contar líneas congestionadas
            lineas_cong = 0
            for j in 1:nTx
                flujo_max_linea = maximum(abs.(fij_sol[j,:]))
                if flujo_max_linea >= Tmax[j] * 0.99
                    lineas_cong += 1
                end
            end
            
            push!(casos_congestion, nombre)
            push!(lineas_congestionadas, lineas_cong)
        end
        
        p5 = plot(casos_congestion, lineas_congestionadas,
            title="Líneas Congestionadas por Caso",
            xlabel="Caso",
            ylabel="Número de Líneas Congestionadas",
            seriestype=:bar,
            legend=false)
        savefig(p5, "lineas_congestionadas_casos.png")
        
        println("📈 Gráficos adicionales guardados:")
        println("   - factor_utilizacion_casos.png")
        println("   - lineas_congestionadas_casos.png")
    end
    
    println("📈 Gráficos comparativos guardados:")
    println("   - comparacion_costos_casos.png")
    println("   - comparacion_vertimiento_casos.png")
    println("   - comparacion_beneficios_casos.png")
    
    return df
end

# Ejecutar todos los casos
if abspath(PROGRAM_FILE) == @__FILE__
    ejecutar_todos_los_casos()
end 