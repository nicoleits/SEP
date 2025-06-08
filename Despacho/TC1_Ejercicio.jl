
# Carga paquetes de julia que serán usados
using JuMP
#using GLPK
using HiGHS
#using Gurobi
#using Ipopt
using Plots
#using DataFrames
using XLSX
# Problema de despacho económico de carga considerando transmision
##################################################################
# DATOS DEL PROBLEMA 
##################################################################
nombre_archivo_datos = "Despacho/datos_3barras.xlsx"
dat_gen     = XLSX.readdata(nombre_archivo_datos, "gen!C5:F6")
dat_lineas  = XLSX.readdata(nombre_archivo_datos,  "lineas!B6:G8")
dat_bus     = XLSX.readdata(nombre_archivo_datos,  "bus!B6:D8")
##################################################################
# DATOS DEL PROBLEMA - congestion - desprendimiento de carga 
# Caso A5
# generador G1 caro y gen 2 se conecta en la barra 3
##################################################################
TIPO_SOLVER = 1; # 1 = HiGHS, 2 = Gurobi, 3= Ipopt 
SB          = 100; # Potencia base

ng      = length(dat_gen[:,1])
ntx     = length(dat_lineas[:,1])
nbus    = length(dat_lineas[:,1])
TIPO_CONEXION_GEN = 1; # 1: G1 B1 Y G2 B2
# 2: G1 B1 Y G2 B3
TIPO_TERCER_PV_GEN = 1; # 1: No se conecta PV
# 2: Se conecta a la barra B1
# 3: Se conecta a la barra B2


if TIPO_TERCER_PV_GEN==1
    cg      = [30 70]
    #cg      = [70 30]
    #cg      = [0.001 30]
    #cg      = [30 0.001]
    #cg      = [0.001 70]
    #cg      = [70 0.001]
    #cg      = [0.001 0.001]

    pmax    = [100 150]
    pmin    = dat_gen[:,3]
elseif TIPO_TERCER_PV_GEN==2
    cg      = [30 70 0.001]
    #cg      = [30 0.001 0.001]
    
    #cg      = [70 30]
    #cg      = [0.001 30]
    #cg      = [30 0.001]
    #cg      = [0.001 70]
    #cg      = [70 0.001]
    #cg      = [0.001 0.001]
    ng      = length(cg)
    pmax    = [100 150 100]
    pmin    = [0 0 0]
    
elseif TIPO_TERCER_PV_GEN==3
    cg      = [30 70 0.001]
    #cg      = [30 0.001 0.001]
    
    #cg      = [70 30]
    #cg      = [0.001 30]
    #cg      = [30 0.001]
    #cg      = [0.001 70]
    #cg      = [70 0.001]
    #cg      = [0.001 0.001]
    ng      = length(cg)
    pmax    = [100 150 100]
    pmin    = [0 0 0]
    


end

pd      = [0 0 170]
txMax   = [100 100 90]
txMin   = -1*txMax
xij     = dat_lineas[:,5]

    
## Modelo de optimizacións
m = Model(HiGHS.Optimizer)
#set_attribute(m, "presolve", "on")
#set_attribute(m, "time_limit", 60.0)
# Define variables de decisión
@variable(m, pmin[i]<=pg[i=1:ng]<=pmax[i])
@variable(m, txMin[i]<=ftx[i=1:ntx]<=txMax[i])
@variable(m, theta[i=1:nbus])
@variable(m, 0<=pr<=10000)

# Define función objetivo
@objective(m, Min, sum( cg[i]*pg[i]+300*pr  for i in 1:ng) )
# Define restricciones
if TIPO_TERCER_PV_GEN==1
    if TIPO_CONEXION_GEN==1
        @constraint(m, balance1, pg[1]-ftx[1]-ftx[2] == pd[1])
        @constraint(m, balance2, pg[2]+ftx[1]-ftx[3] == pd[2])
        @constraint(m, balance3, pr+ftx[2]+ftx[3] == pd[3])
    elseif TIPO_CONEXION_GEN==2
        @constraint(m, balance1, pg[1]-ftx[1]-ftx[2] == pd[1])
        @constraint(m, balance2, pr+ftx[1]-ftx[3] == pd[2])
        @constraint(m, balance3, pg[2]+ftx[2]+ftx[3] == pd[3])
        
    end
elseif TIPO_TERCER_PV_GEN==2
    if TIPO_CONEXION_GEN==1
        @constraint(m, balance1, pg[1]+pg[3]-ftx[1]-ftx[2] == pd[1])
        @constraint(m, balance2, pg[2]+ftx[1]-ftx[3] == pd[2])
        @constraint(m, balance3, pr+ftx[2]+ftx[3] == pd[3])
    elseif TIPO_CONEXION_GEN==2
        @constraint(m, balance1, pg[1]+pg[3]-ftx[1]-ftx[2] == pd[1])
        @constraint(m, balance2, pr+ftx[1]-ftx[3] == pd[2])
        @constraint(m, balance3, pg[2]+ftx[2]+ftx[3] == pd[3])
        
    end
elseif TIPO_TERCER_PV_GEN==3
    if TIPO_CONEXION_GEN==1
        @constraint(m, balance1, pg[1]-ftx[1]-ftx[2] == pd[1])
        @constraint(m, balance2, pg[2]+pg[3]+ftx[1]-ftx[3] == pd[2])
        @constraint(m, balance3, pr+ftx[2]+ftx[3] == pd[3])
    elseif TIPO_CONEXION_GEN==2
        @constraint(m, balance1, pg[1]-ftx[1]-ftx[2] == pd[1])
        @constraint(m, balance2, pr+pg[3]+ftx[1]-ftx[3] == pd[2])
        @constraint(m, balance3, pg[2]+ftx[2]+ftx[3] == pd[3])
        
    end


end
@constraint(m,consTx1,ftx[1]/SB==(theta[1]-theta[2])/xij[1])
@constraint(m,consTx2,ftx[2]/SB==(theta[1]-theta[3])/xij[2])
@constraint(m,consTx3,ftx[3]/SB==(theta[2]-theta[3])/xij[3])


print(m)
optimize!(m)
result = Dict();
result["Pg"] = value.(pg);
result["Pr"] = value.(pr);

result["fTx"] = value.(ftx);
result["theta"] = value.(theta);
result["ct"] = objective_value(m);
result["cmg1"] = dual(balance1);
result["cmg2"] = dual(balance2);
result["cmg3"] = dual(balance3);
result

