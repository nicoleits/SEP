# Lista de package que se usaran
using JuMP
using GLPK
using HiGHS
using Gurobi
using Plots
using DataFrames
# Problema de despacho económico de carga considerando funcion objetivo cuadratica
# sin restriciones 
TIPO_SOLVER = 1; # 1 = HiGHS, 2 = Gurobi 
index_P = 1:2
index_constraints = 1
#Pmax = [200 200]
Pmax = [100 180]

Pmin = [0 0]
#Pmin = [0 80]

cg   = [30 70]
cg2  = [0.01 0.015]
####################################################################
# Funciones de modelo lineal y no lineal
####################################################################
# modelo no lineal
function fcn_despacho_PNL(;Pd,TIPO_SOLVER,cg,cg2,Pmax,Pmin,index_P,index_constraints)
    # Datos del problema

    
    ## Modelo de optimizacións
    if TIPO_SOLVER==1
    #m = Model(GLPK.Optimizer)
        m = Model(HiGHS.Optimizer)
        #set_attribute(m, "presolve", "on")
        #set_attribute(m, "time_limit", 60.0)
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

    #print(m);
    optimize!(m)
    
    result = Dict()
    result["Pg"] = value.(P);
    result["ct"] = objective_value(m);
    result["cmg"] = dual(balance);
    result["dualPmax"] = dual.(PmaxConst);
    result["dualPmin"] = dual.(PminConst);
    
    
    return result

end
# modelo lineal
function fcn_despacho_PL(;Pd,TIPO_SOLVER,cg,Pmax,Pmin,index_P,index_constraints)
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
# calculo de costos en central 
function fcn_costo_gen_balance_NL(;p,cgCostos,cmg)
   a = cgCostos[1];
   b = cgCostos[2];
   c  = cgCostos[3];
   
    IC = 2*a*p+b;
    CT = a*p^2+b*p+c;
    ingreso = cmg*p;
    balanceGen = ingreso-CT;
    result = Dict()
    result["IC"] = IC
    result["CT"] = CT
    result["Ingreso"] = ingreso
    result["balance_gen"] = balanceGen
    

    return result
end
# calculo de costos en central lineal 
function fcn_costo_gen_balance_L(;p,cgCostos,cmg)
    b = cgCostos[2];
    
     IC = b;
     CT = b*p;
     ingreso = cmg*p;
     balanceGen = ingreso-CT;
 
     result = Dict();
     result["IC"] = IC;
     result["CT"] = CT;
     result["Ingreso"] = ingreso
     result["balance_gen"] = balanceGen
 
     
     return result
end
 

####################################################################
# Modifica la demanda en un mega, de 170
####################################################################
PdVect = [170 171]
n = length(PdVect)
ng= length(cg)
resultPL = Dict()
resultPNL = Dict()

for i in 1:n
    resultPNL[string(i)] = fcn_despacho_PNL(;Pd=PdVect[i],TIPO_SOLVER=TIPO_SOLVER,
                                            cg=cg,cg2=cg2,Pmax=Pmax,Pmin=Pmin,
                                            index_P=index_P,index_constraints=index_constraints)
    resultPL[string(i)]  = fcn_despacho_PL(;Pd=PdVect[i],TIPO_SOLVER=TIPO_SOLVER,
                                            cg=cg,Pmax=Pmax,Pmin=Pmin,
                                            index_P=index_P,index_constraints=index_constraints)
    
    for j in 1:ng
        resultPNL[string(i)][string(j)]=Dict()
        aux1=fcn_costo_gen_balance_NL(;p=resultPNL[string(i)]["Pg"][j],
                                    cgCostos=[cg2[j] cg[j] 0],cmg=resultPNL[string(i)]["cmg"]);
        resultPNL[string(i)][string(j)] = aux1;
        resultPL[string(i)][string(j)]=Dict()
        aux1=fcn_costo_gen_balance_L(;p=resultPL[string(i)]["Pg"][j],
                                    cgCostos=[cg2[j] cg[j] 0],cmg=resultPL[string(i)]["cmg"]);
        resultPL[string(i)][string(j)] = aux1;
    end
end



###########################################
# Comparacion no lineal
###########################################

CASO = 1
resultPNL[string(CASO)]["Pg"]
resultPNL[string(CASO)]["ct"]
resultPNL[string(CASO)]["cmg"]
resultPNL[string(CASO)]["dualPmax"]
resultPNL[string(CASO)]["dualPmin"]
resultPNL[string(CASO)]["1"]
resultPNL[string(CASO)]["2"]


CASO = 2
resultPNL[string(CASO)]["Pg"]
resultPNL[string(CASO)]["ct"]
resultPNL[string(CASO)]["cmg"]
resultPNL[string(CASO)]["dualPmax"]
resultPNL[string(CASO)]["dualPmin"]
resultPNL[string(CASO)]["1"]
resultPNL[string(CASO)]["2"]

resultPNL[string(2)]["ct"]-resultPNL[string(1)]["ct"]


###########################################
# Comparacion lineal
###########################################

CASO = 1
resultPL[string(CASO)]["Pg"]
resultPL[string(CASO)]["ct"]
resultPL[string(CASO)]["cmg"]
resultPL[string(CASO)]["dualPmax"]
resultPL[string(CASO)]["dualPmin"]
resultPL[string(CASO)]["1"]
resultPL[string(CASO)]["2"]


CASO = 2
resultPL[string(CASO)]["Pg"]
resultPL[string(CASO)]["ct"]
resultPL[string(CASO)]["cmg"]
resultPL[string(CASO)]["dualPmax"]
resultPL[string(CASO)]["dualPmin"]
resultPL[string(CASO)]["1"]
resultPL[string(CASO)]["2"]

resultPL[string(2)]["ct"]-resultPL[string(1)]["ct"]

###########################################
# Comparacion caso lineal y no lineal
###########################################

CASO = 1
resultPL[string(CASO)]["Pg"]
resultPNL[string(CASO)]["Pg"]
resultPL[string(CASO)]["ct"]
resultPNL[string(CASO)]["ct"]
resultPL[string(CASO)]["cmg"]
resultPNL[string(CASO)]["cmg"]
resultPL[string(CASO)]["dualPmax"]
resultPNL[string(CASO)]["dualPmax"]
resultPL[string(CASO)]["dualPmin"]
resultPNL[string(CASO)]["dualPmin"]


