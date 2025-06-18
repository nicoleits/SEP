using XLSX
using Plots

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
    
    # Configurar variables globales
    global TIPO_CASO_CON_SIN_ER = tipo_caso
    global TIPO_SOLVER = tipo_solver
    global TIPO_SERIE_ERV = tipo_serie
    
    # Ejecutar el modelo
    try
        include("UC_Ex8.jl")
        
        println("\nVerificando resultados del modelo:")
        println("Costo total: $(result2["ct"])")
        println("Dimensiones de Pg: $(size(result2["Pg"]))")
        println("Dimensiones de pEr: $(size(pEr))")
        println("Primeras filas de pEr:")
        println(pEr[1:3,:])
        
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
            
            # Guardar potencias generadas
            sheet["C4"] = result2["Pg"]
            
            # Si es caso con renovables, agregar potencias renovables en filas 13 y 14
            if tipo_caso == 1
                sheet["A13"] = "WT1"
                sheet["B13"] = "Eólica"
                sheet["A14"] = "WT2"
                sheet["B14"] = "Eólica"
                sheet["C13"] = pEr[:,1]
                sheet["C14"] = pEr[:,2]
            end
            
            # Guardar resultados de reserva
            sheet = xf["Reserva"]
            sheet["A1"] = "Resultados de Reserva"
            sheet["C4"] = result2["Rg"]
            
            # Guardar resultados de flujos
            sheet = xf["Flujos"]
            sheet["A1"] = "Resultados de Flujos"
            sheet["E4"] = result2["fij"]
            
            # Guardar resultados de encendido
            sheet = xf["Encendido"]
            sheet["A1"] = "Resultados de Encendido"
            sheet["C4"] = result2["ug"]
            
            # Guardar resultados de costos marginales
            sheet = xf["Costos_Marginales"]
            sheet["A1"] = "Resultados de Costos Marginales"
            sheet["C4"] = result2["cmg"]
            
            # Calcular y guardar resultados de vertimiento
            sheet = xf["Vertimiento"]
            sheet["A1"] = "Análisis de Vertimiento"
            sheet["A3"] = "Concepto"
            
            # Calcular generación total por hora
            generacion_total = zeros(nT)
            for i in 1:ng
                generacion_total += result2["Pg"][i,:]
            end
            if tipo_caso == 1
                generacion_total += pEr[:,1] + pEr[:,2]
            end
            
            # Calcular demanda total por hora y convertir a matriz 1xn
            demanda_total = reshape(sum(pd, dims=2), 1, :)
            
            # Calcular vertimiento
            vertimiento = reshape(generacion_total, 1, :) - demanda_total
            
            # Guardar resultados en la hoja de vertimiento
            sheet["A4"] = "Generación Total"
            sheet["A5"] = "Demanda Total"
            sheet["A6"] = "Vertimiento"
            sheet["C4"] = reshape(generacion_total, 1, :)
            sheet["C5"] = demanda_total
            sheet["C6"] = vertimiento
            
            # Calcular ingresos y egresos por central
            ingresos = zeros(ng, nT)
            egresos = zeros(ng, nT)
            for i in 1:ng
                for t in 1:nT
                    ingresos[i,t] = result2["cmg"][busGen[i],t] * result2["Pg"][i,t]
                    egresos[i,t] = cv[i] * result2["Pg"][i,t]
                end
            end
            
            # Si es caso con renovables, calcular ingresos y egresos de las renovables
            if tipo_caso == 1
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
            
            # Copiar información de vertimiento
            sheet["A4"] = "Análisis de Vertimiento"
            sheet["A5"] = "Generación Total"
            sheet["A6"] = "Demanda Total"
            sheet["A7"] = "Vertimiento"
            sheet["C5"] = reshape(generacion_total, 1, :)
            sheet["C6"] = demanda_total
            sheet["C7"] = vertimiento
            
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
            if tipo_caso == 1
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
    catch e
        println("Error al ejecutar el caso: ", e)
        if tipo_caso == 0
            println("Este error es esperado para el caso sin energía renovable")
        else
            println("Este error no es esperado para el caso con energía renovable")
        end
    end
end

# Ejecutar diferentes casos
println("\nIniciando ejecución de casos...")

# Casos sin energía renovable
println("\nEjecutando caso sin energía renovable...")
ejecutar_caso(0, 1, 1)

# Casos con energía renovable
println("\nEjecutando casos con energía renovable...")
for tipo_serie in 1:9
    println("\nEjecutando perfil $tipo_serie...")
    ejecutar_caso(1, 1, tipo_serie)
end

println("\nEjecución de todos los casos completada") 