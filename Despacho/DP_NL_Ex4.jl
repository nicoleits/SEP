# Lista de package que se usaran
using JuMP
#using GLPK
using HiGHS
using Gurobi
using Plots
using DataFrames
# Problema de despacho económico de carga considerando funcion objetivo cuadratica
# sin restriciones 
TIPO_SOLVER = 1; # 1 = HiGHS, 2 = Gurobi 
index_P = 1:2
index_constraints = 1
Pmax = [100 150]
Pmin = [0 0]
cg   = [30 70]
cg2  = [0.01 0.015]

####################################################################
# Funciones de modelo lineal y no lineal
####################################################################

function fcn_despacho_PNL(;Pd,TIPO_SOLVER,cg,cg2,Pmax,Pmin,index_P,index_constraints)
    # Datos del problema

    
    ## Modelo de optimizacións
    if TIPO_SOLVER==1
    #m = Model(GLPK.Optimizer)
        m = Model(HiGHS.Optimizer)
        set_attribute(m, "presolve", "on")
        set_attribute(m, "time_limit", 60.0)
    elseif TIPO_SOLVER==2
        m = Model(Gurobi.Optimizer)
    end
    # Define variables de decisión 
    @variable(m,P[index_P]>=0)
    # Define función objetivo
    @objective(m, Min, sum( cg[i]*P[i]+cg2[i]*P[i]^2  for i in index_P) )
    # Define restricciones
    @constraint(m, balance, sum(P) == Pd)
    @constraint(m, PmaxConst[i in index_P], P[i]<=Pmax[i])
    @constraint(m, PminConst[i in index_P], P[i]>=Pmin[i])

    print(m)
    optimize!(m)
    result = Dict()
    result["Pg"] = value.(P);
    result["ct"] = objective_value(m);
    result["cmg"] = dual(balance);
    result["dualPmax"] = dual.(PmaxConst);
    result["dualPmin"] = dual.(PminConst);
    
    
    return result

end
# Modelo lineal
function fcn_despacho_PL(;Pd,TIPO_SOLVER,cg,Pmax,Pmin,index_P,index_constraints)
    # Datos del problema
    index_P = 1:2
    index_constraints = 1
    Pmax = [100 150]
    Pmin = [0 0]
    cg   = [30 70]
    cg2  = [0.1 0.15]
    
    ## Modelo de optimizacións
    if TIPO_SOLVER==1
    #m = Model(GLPK.Optimizer)
        m = Model(HiGHS.Optimizer)
        set_attribute(m, "presolve", "on")
        set_attribute(m, "time_limit", 60.0)
    elseif TIPO_SOLVER==2
        m = Model(Gurobi.Optimizer)
    end
    # Define variables de decisión 
    @variable(m,P[index_P]>=0)
    # Define función objetivo
    @objective(m, Min, sum( cg[i]*P[i]  for i in index_P) )
    # Define restricciones
    @constraint(m, balance, sum(P) == Pd)
    @constraint(m, PmaxConst[i in index_P], P[i]<=Pmax[i])
    @constraint(m, PminConst[i in index_P], P[i]>=Pmin[i])

    print(m)
    optimize!(m)
    result = Dict()
    result["Pg"] = value.(P);
    result["ct"] = objective_value(m);
    result["cmg"] = dual(balance);
    result["dualPmax"] = dual.(PmaxConst);
    result["dualPmin"] = dual.(PminConst);
    
    
    return result

end

####################################################################
# Modifica la demanda en un mega, de 170
####################################################################
PdVect = [170 171]
PminMatrix = [0 0;
              0 70;
              0 80]

n1 = length(PdVect)
n2 = length(PminMatrix)

resultPL = Dict()
resultPNL = Dict()

for i in 1:n1
    resultPNL[string(i)] = Dict()
    resultPL[string(i)] = Dict()
    
    for j in 1:n2
        resultPNL[string(i)][string(j)] = fcn_despacho_PNL(;Pd=PdVect[i],TIPO_SOLVER=TIPO_SOLVER,
                                                cg=cg,cg2=cg2,Pmax=Pmax,Pmin=Pmin,
                                                index_P=index_P,index_constraints=index_constraints)
        resultPL[string(i)][string(j)]  = fcn_despacho_PL(;Pd=PdVect[i],TIPO_SOLVER=TIPO_SOLVER,
                                                cg=cg,Pmax=Pmax,Pmin=Pmin,
                                                index_P=index_P,index_constraints=index_constraints)

    end
end
###########################################
# Comparacion no lineal
###########################################

CASO_PD = 1
CASO_PMIN=1
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["Pg"]
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["ct"]
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["cmg"]
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["dualPmax"]
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["dualPmin"]

CASO_PD = 1
CASO_PMIN=1
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["Pg"]
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["ct"]
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["cmg"]
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["dualPmax"]
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["dualPmin"]

resultPNL[string(CASO_PD)][string(CASO_PMIN)]["ct"]-resultPNL[string(CASO_PD)][string(CASO_PMIN)]["ct"]


###########################################
# Comparacion lineal
###########################################

CASO_PD = 1
CASO_PMIN=1
resultPL[string(CASO_PD)][string(CASO_PMIN)]["Pg"]
resultPL[string(CASO_PD)][string(CASO_PMIN)]["ct"]
resultPL[string(CASO_PD)][string(CASO_PMIN)]["cmg"]
resultPL[string(CASO_PD)][string(CASO_PMIN)]["dualPmax"]
resultPL[string(CASO_PD)][string(CASO_PMIN)]["dualPmin"]

CASO_PD = 2
CASO_PMIN=1
resultPL[string(CASO_PD)][string(CASO_PMIN)]["Pg"]
resultPL[string(CASO_PD)][string(CASO_PMIN)]["ct"]
resultPL[string(CASO_PD)][string(CASO_PMIN)]["cmg"]
resultPL[string(CASO_PD)][string(CASO_PMIN)]["dualPmax"]
resultPL[string(CASO_PD)][string(CASO_PMIN)]["dualPmin"]

resultPL[string(CASO_PD)][string(CASO_PMIN)]["ct"]-resultPL[string(CASO_PD)][string(CASO_PMIN)]["ct"]

###########################################
# Comparacion caso lineal y no lineal
###########################################

CASO_PD = 1
CASO_PMIN=1
resultPL[string(CASO_PD)][string(CASO_PMIN)]["Pg"]
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["Pg"]
resultPL[string(CASO_PD)][string(CASO_PMIN)]["ct"]
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["ct"]
resultPL[string(CASO_PD)][string(CASO_PMIN)]["cmg"]
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["cmg"]
resultPL[string(CASO_PD)][string(CASO_PMIN)]["dualPmax"]
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["dualPmax"]
resultPL[string(CASO_PD)][string(CASO_PMIN)]["dualPmin"]
resultPNL[string(CASO_PD)][string(CASO_PMIN)]["dualPmin"]


