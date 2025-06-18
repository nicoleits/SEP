module FunPredesp

using JuMP
using HiGHS
using DataFrames
using XLSX
using LinearAlgebra

export resolver_UC

function resolver_UC(tipo_caso::Int, tipo_solver::Int, tipo_serie::Int)
    # Selección de archivo de datos
    if tipo_caso == 0
        NOMBRE_ARCHIVO_DATOS = "UC_datEx8_sinER.xlsx"
    else
        NOMBRE_ARCHIVO_DATOS = "UC_datEx8.xlsx"
    end
    sB = 100

    # Leer datos
    if tipo_caso == 0
        datGen = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "Gen!C4:O12")
        datDem = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "dem!A4:J27")
        datLineas = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "Lineas!A4:G14")
        pEr = Array{Float64}(undef, 0, 0)
    else
        datGen = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "Gen!C4:O14")
        datDem = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "dem!A4:J27")
        datLineas = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "Lineas!A4:G14")
        if tipo_serie == 1
            datEr = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "ERV!C5:AB6")
        elseif tipo_serie == 2
            datEr = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "ERV!C13:AB14")
        elseif tipo_serie == 3
            datEr = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "ERV!C20:AB21")
        elseif tipo_serie == 4
            datEr = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "ERV!C27:AB28")
        elseif tipo_serie == 5
            datEr = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "ERV!C35:AB36")
        elseif tipo_serie == 6
            datEr = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "ERV!C42:AB43")
        elseif tipo_serie == 7
            datEr = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "ERV!C49:AB50")
        elseif tipo_serie == 8
            datEr = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "ERV!C56:AB57")
        elseif tipo_serie == 9
            datEr = XLSX.readdata(NOMBRE_ARCHIVO_DATOS, "ERV!C63:AB64")
        end
        pEr = datEr[:,3:end]'
    end

    # Parámetros
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

    # Matrices de incidencia
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
    Y = Matrix(Diagonal(1.0 ./ xij))

    # Modelo
    if tipo_solver == 1
        m = Model(HiGHS.Optimizer)
    elseif tipo_solver == 2
        m = Model(Gurobi.Optimizer)
    elseif tipo_solver == 3
        m = Model(Ipopt.Optimizer)
    end

    @variable(m,pg[1:ng,1:nT])
    @variable(m,rg[1:ng,1:nT])
    @variable(m,fTx[1:nTx,1:nT])
    @variable(m,theta[1:nBus,1:nT])
    @variable(m,ug[1:ng,1:nT], Bin)
    @variable(m,uEnc[1:ng,1:nT], Bin)
    @variable(m,uApa[1:ng,1:nT], Bin)

    @objective(m, Min, sum(sum(cv[i]*pg[i,j] + cEnc[i]*uEnc[i,j] + cApa[i]*uApa[i,j] for i in 1:ng) for j in 1:nT))

    @constraint(m, balance[j in 1:nT], Ag*pg[:,j] - A*fTx[:,j] .== Ad*pd[j,:])
    @constraint(m, flujoTx[j=1:nT], fTx[:,j] .== Y*A'*theta[:,j])

    iter = 0
    for i in 1:ng
        if tipoGen[i] == 2 && tipo_caso == 1 && size(pEr,1) > 0
            iter += 1
            @constraint(m, [j in 1:nT], pg[i,j]+rg[i,j] <= pEr[j,iter]*ug[i,j])
            @constraint(m, [j in 1:nT], pg[i,j] >= pmin[i]*ug[i,j])
            @constraint(m, [j in 1:nT], rg[i,j] == 0)
        else
            @constraint(m, [j in 1:nT], pg[i,j]+rg[i,j] <= pmax[i]*ug[i,j])
            @constraint(m, [j in 1:nT], pg[i,j] >= pmin[i]*ug[i,j])
        end
    end

    @constraint(m, [i=1:nTx,j=1:nT], fTx[i,j] <= Tmax[i])
    @constraint(m, [i=1:nTx,j=1:nT], fTx[i,j] >= -Tmax[i])

    for i in 1:ng
        if aportaReserva[i] == 1
            @constraint(m, [j in 1:nT], rg[i,j] >= kReserva[i]*pmax[i]*ug[i,j])
        end
    end
    @constraint(m, ramp_up[i in 1:ng, j in 2:nT], pg[i,j]-pg[i,j-1]+rg[i,j] <= R_up[i])
    @constraint(m, ramp_dw[i in 1:ng, j in 2:nT], pg[i,j]-pg[i,j-1] >= -R_do[i])
    @constraint(m, [i in 1:ng], ug[i,1] == uEnc[i,1]-uApa[i,1])
    @constraint(m, [i in 1:ng], ug[i,1] >= uEnc[i,1])
    @constraint(m, [i in 1:ng], 1-ug[i,1] >= uApa[i,1])
    @constraint(m, [i in 1:ng, j in 2:nT], ug[i,j] == ug[i,j-1] + uEnc[i,j] - uApa[i,j])

    for i in 1:ng
        rang1 = t_up[i]:nT
        for j in rang1
            rang2 = (j-t_up[i]+1):j
            @constraint(m, ug[i,j] >= sum(uEnc[i,k] for k in rang2))
        end
    end
    @constraint(m, [i in 1:ng, j in 2:t_up[i]], ug[i,j] >= sum(uEnc[i,k] for k in 1:j))
    for i in 1:ng
        rang1 = t_do[i]:nT
        for j in rang1
            rang2 = (j-t_do[i]+1):j
            @constraint(m, 1-ug[i,j] >= sum(uApa[i,k] for k in rang2))
        end
    end
    @constraint(m, [i in 1:ng, j in 2:t_do[i]], 1-ug[i,j] >= sum(uApa[i,k] for k in 1:j))

    optimize!(m)

    # Primera optimización completada - ahora fijar variables binarias y optimizar despacho económico
    ugSol = value.(ug)
    uEncSol = value.(uEnc)
    uApaSol = value.(uApa)
    
    # Fijar las variables binarias con los valores obtenidos
    fix.(ug, ugSol; force=true)
    fix.(uEnc, uEncSol; force=true)
    fix.(uApa, uApaSol; force=true)
    
    # Quitar la naturaleza binaria de las variables
    unset_binary.(ug)
    unset_binary.(uEnc)
    unset_binary.(uApa)
    
    # Segunda optimización - despacho económico
    optimize!(m)

    result2 = Dict()
    result2["Pg"] = value.(pg)
    result2["Rg"] = value.(rg)
    result2["ug"] = value.(ug)
    result2["fij"] = value.(fTx)
    result2["ct"] = objective_value(m)
    
    # Calcular costos marginales después de la segunda optimización
    aux = zeros(nBus, nT)
    for i in 1:nT
        aux[:,i] = dual.(balance[i])
    end
    result2["cmg"] = aux

    return Dict(
        "Pg" => result2["Pg"],
        "Rg" => result2["Rg"],
        "ug" => result2["ug"],
        "fij" => result2["fij"],
        "ct" => result2["ct"],
        "cmg" => result2["cmg"],
        "pEr" => pEr,
        "datGen" => datGen,
        "pd" => pd,
        "horasDia" => horasDia,
        "tipoGen" => tipoGen,
        "busGen" => busGen
    )
end

end # module 