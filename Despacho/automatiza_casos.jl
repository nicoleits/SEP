using JuMP
using HiGHS
using XLSX
using DataFrames
using Plots
using StatsPlots

# Definición de los 16 casos
casos = [
    # N° Caso, cg1, cg2, cg3, barra PV, Tx23max
    (1, 30.0, 70.0, missing, missing, 100.0),
    (2, 70.0, 30.0, missing, missing, 100.0),
    (3, 0.001, 30.0, missing, missing, 100.0),
    (4, 30.0, 0.001, missing, missing, 100.0),
    (5, 0.001, 0.001, missing, missing, 100.0),
    (6, 30.0, 70.0, 0.001, 1, 100.0),
    (7, 30.0, 70.0, 0.001, 2, 100.0),
    (8, 30.0, 0.001, 0.001, 1, 100.0),
    (9, 30.0, 70.0, missing, missing, 90.0),
    (10, 70.0, 30.0, missing, missing, 90.0),
    (11, 0.001, 30.0, missing, missing, 90.0),
    (12, 30.0, 0.001, missing, missing, 90.0),
    (13, 0.001, 0.001, missing, missing, 90.0),
    (14, 30.0, 70.0, 0.001, 1, 90.0),
    (15, 30.0, 70.0, 0.001, 2, 90.0),
    (16, 30.0, 0.001, 0.001, 1, 90.0)
]

# Función para resolver el modelo para un caso
function resolver_caso(cg1, cg2, cg3, barra_pv, tx23max)
    # Cargar datos base
    nombre_archivo_datos = "Despacho/datos_3barras.xlsx"
    dat_gen     = XLSX.readdata(nombre_archivo_datos, "gen!C5:F6")
    dat_lineas  = XLSX.readdata(nombre_archivo_datos,  "lineas!B6:G8")
    dat_bus     = XLSX.readdata(nombre_archivo_datos,  "bus!B6:D8")
    SB = 100
    # Ajustar parámetros según el caso
    if cg3 === missing
        cg = [cg1, cg2]
        pmax = [100, 150]
        pmin = dat_gen[:,3]
        ng = 2
        TIPO_TERCER_PV_GEN = 1
    else
        cg = [cg1, cg2, cg3]
        pmax = [100, 150, 100]
        pmin = [0, 0, 0]
        ng = 3
        TIPO_TERCER_PV_GEN = 2
    end
    ntx = 3
    nbus = 3
    pd = [0, 0, 170]
    txMax = [100, 100, tx23max]
    txMin = -1 .* txMax
    xij = dat_lineas[:,5]
    # Modelo
    m = Model(HiGHS.Optimizer)
    @variable(m, pmin[i]<=pg[i=1:ng]<=pmax[i])
    @variable(m, txMin[i]<=ftx[i=1:ntx]<=txMax[i])
    @variable(m, theta[i=1:nbus])
    @variable(m, 0<=pr<=10000)
    @objective(m, Min, sum( cg[i]*pg[i]+300*pr  for i in 1:ng) )
    if TIPO_TERCER_PV_GEN==1
        @constraint(m, balance1, pg[1]-ftx[1]-ftx[2] == pd[1])
        @constraint(m, balance2, pg[2]+ftx[1]-ftx[3] == pd[2])
        @constraint(m, balance3, pr+ftx[2]+ftx[3] == pd[3])
    else
        if barra_pv == 1
            @constraint(m, balance1, pg[1]+pg[3]-ftx[1]-ftx[2] == pd[1])
            @constraint(m, balance2, pg[2]+ftx[1]-ftx[3] == pd[2])
            @constraint(m, balance3, pr+ftx[2]+ftx[3] == pd[3])
        elseif barra_pv == 2
            @constraint(m, balance1, pg[1]-ftx[1]-ftx[2] == pd[1])
            @constraint(m, balance2, pg[2]+pg[3]+ftx[1]-ftx[3] == pd[2])
            @constraint(m, balance3, pr+ftx[2]+ftx[3] == pd[3])
        end
    end
    @constraint(m,consTx1,ftx[1]/SB==(theta[1]-theta[2])/xij[1])
    @constraint(m,consTx2,ftx[2]/SB==(theta[1]-theta[3])/xij[2])
    @constraint(m,consTx3,ftx[3]/SB==(theta[2]-theta[3])/xij[3])
    optimize!(m)
    # Resultados
    Pg = value.(pg)
    Pr = value(pr)
    fTx = value.(ftx)
    theta_v = value.(theta)
    ct = objective_value(m)
    cmg1 = dual(balance1)
    cmg2 = dual(balance2)
    cmg3 = dual(balance3)
    return (ct, cmg1, cmg2, cmg3, Pg, Pr, fTx, theta_v)
end

# DataFrame para resultados
# Unidades:
#   CostoTotal: USD
#   CMg1, CMg2, CMg3: USD/MWh
#   Pg1, Pg2, Pg3, Pr, fTx1, fTx2, fTx3: MW
#   theta1, theta2, theta3: radianes
#   BalanceG1, BalanceG2, BalanceG3: USD
#   ConPV: Bool (true si el caso tiene PV)
resultados = DataFrame(Caso=Int[], cg1=Float64[], cg2=Float64[], cg3=Union{Missing,Float64}[], PV=Union{Missing,Int}[], Tx23max=Float64[],
    CostoTotal=Float64[], CMg1=Float64[], CMg2=Float64[], CMg3=Float64[], Pg1=Float64[], Pg2=Float64[], Pg3=Union{Missing,Float64}[], Pr=Float64[],
    fTx1=Float64[], fTx2=Float64[], fTx3=Float64[], theta1=Float64[], theta2=Float64[], theta3=Float64[],
    BalanceG1=Float64[], BalanceG2=Float64[], BalanceG3=Union{Missing,Float64}[], ConPV=Bool[])

for caso in casos
    (n, cg1, cg2, cg3, pv, tx23max) = caso
    ct, cmg1, cmg2, cmg3, Pg, Pr, fTx, theta_v = resolver_caso(cg1, cg2, cg3, pv, tx23max)
    Pg1 = Pg[1]
    Pg2 = Pg[2]
    Pg3 = cg3 === missing ? missing : Pg[3]
    # Cálculo del balance económico de cada generador
    balance_g1 = cmg1 * Pg1 - cg1 * Pg1
    balance_g2 = cmg2 * Pg2 - cg2 * Pg2
    balance_g3 = cg3 === missing ? missing : (cmg3 * Pg3 - cg3 * Pg3)
    con_pv = cg3 === missing ? false : true
    push!(resultados, (n, cg1, cg2, cg3, pv, tx23max, ct, cmg1, cmg2, cmg3, Pg1, Pg2, Pg3, Pr, fTx[1], fTx[2], fTx[3], theta_v[1], theta_v[2], theta_v[3], balance_g1, balance_g2, balance_g3, con_pv))
end

# Guardar resultados en Excel
XLSX.writetable("Despacho/resultados_casos.xlsx", Tables.columntable(resultados); sheetname="Resultados", overwrite=true)

# Gráficos
plot(resultados.Caso, resultados.CostoTotal, xlabel="Caso", ylabel="Costo Total (USD)", title="Costo Total de Operación por Caso", legend=false)
savefig("Despacho/grafico_costo_total.png")

plot(resultados.Caso, resultados.CMg1, label="CMg1", xlabel="Caso", ylabel="USD/MWh", title="Costos Marginales por Barra")
plot!(resultados.Caso, resultados.CMg2, label="CMg2")
plot!(resultados.Caso, resultados.CMg3, label="CMg3")
savefig("Despacho/grafico_costos_marginales.png")

plot(resultados.Caso, resultados.Pg1, label="G1", xlabel="Caso", ylabel="Generación (MW)", title="Generación por Generador")
plot!(resultados.Caso, resultados.Pg2, label="G2")
if any(.!ismissing.(resultados.Pg3))
    plot!(resultados.Caso, [ismissing(x) ? NaN : x for x in resultados.Pg3], label="G3")
end
savefig("Despacho/grafico_generacion.png")

plot(resultados.Caso, resultados.fTx1, label="Tx1", xlabel="Caso", ylabel="Flujo (MW)", title="Flujos de Transmisión")
plot!(resultados.Caso, resultados.fTx2, label="Tx2")
plot!(resultados.Caso, resultados.fTx3, label="Tx3")
savefig("Despacho/grafico_flujos.png")

plot(resultados.Caso, resultados.Pr, xlabel="Caso", ylabel="Desprendimiento (MW)", title="Desprendimiento de Carga", legend=false)
savefig("Despacho/grafico_desprendimiento.png")

# Gráficos comparativos según entrada de PV
# Costo total
@df resultados groupedbar(:Caso, :CostoTotal, group=:ConPV, bar_position=:dodge, xlabel="Caso", ylabel="Costo Total (USD)", title="Costo Total: Casos con y sin PV", legend=:topright)
savefig("Despacho/grafico_comparativo_costo_total.png")
# Desprendimiento de carga
@df resultados groupedbar(:Caso, :Pr, group=:ConPV, bar_position=:dodge, xlabel="Caso", ylabel="Desprendimiento de Carga (MW)", title="Desprendimiento de Carga: Casos con y sin PV", legend=:topright)
savefig("Despacho/grafico_comparativo_desprendimiento.png")
# Balance económico de G1 y G2 (G3 solo si existe)
@df resultados groupedbar(:Caso, [:BalanceG1 :BalanceG2], group=:ConPV, bar_position=:dodge, xlabel="Caso", ylabel="Balance Económico (USD)", title="Balance Económico G1 y G2: Casos con y sin PV", legend=:topright)
savefig("Despacho/grafico_comparativo_balance_g1g2.png")
if any(.!ismissing.(resultados.BalanceG3))
    @df resultados groupedbar(:Caso, :BalanceG3, group=:ConPV, bar_position=:dodge, xlabel="Caso", ylabel="Balance Económico (USD)", title="Balance Económico G3: Casos con y sin PV", legend=:topright)
    savefig("Despacho/grafico_comparativo_balance_g3.png")
end 