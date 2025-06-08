# Problema considerando las perdidas
# Para entender el comportamiento, modelaremos con y sin consideracion perdidas
# Lista de package que se usaran
using JuMP
using GLPK
using HiGHS
#using Gurobi
using Ipopt
using Plots
using DataFrames
# Problema de despacho económico de carga considerando funcion objetivo cuadratica
# sin restriciones 
TIPO_SOLVER = 3; # 1 = HiGHS, 2 = Gurobi, 3= Ipopt 
index_P = 1:2
index_constraints = 1
Pmax = [400 400]
Pmin = [70 70]
cg   = [7 7] # Costo variable
aTx  = 0.0002 # Coef. de las pérdidas del sistema

####################################################################
# Funciones de modelo lineal y no lineal
####################################################################
# modelo no lineal
function fcn_despacho_PNL(;Pd,aTx,TIPO_SOLVER,cg,Pmax,Pmin,index_P,index_constraints)
    # Datos del problema

    
    ## Modelo de optimizacións
    if TIPO_SOLVER==1
    #m = Model(GLPK.Optimizer)
        m = Model(HiGHS.Optimizer)
        set_attribute(m, "presolve", "on")
        set_attribute(m, "time_limit", 60.0)
    elseif TIPO_SOLVER==2
        m = Model(Gurobi.Optimizer)
    elseif TIPO_SOLVER==3
        m = Model(Ipopt.Optimizer)
    end
    # Define variables de decisión 
    @variable(m,P[index_P]>=0)
    # Define función objetivo
    @objective(m, Min, sum( cg[i]*P[i]  for i in index_P) )
    # Define restricciones
    @constraint(m, balance, sum(P) == Pd+aTx*P[1]^2)
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
    elseif TIPO_SOLVER==3
        m = Model(Ipopt.Optimizer)
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
     result["Ingreso"] = ingreso;
     result["balance_gen"] = balanceGen
 
     
     return result
end
 

####################################################################
# Modifica la demanda en un mega, de 170
####################################################################
PdVect = [500 501]
n = length(PdVect)
ng= length(cg)
resultPL = Dict()
resultPNL = Dict()

for i in 1:n
    resultPNL[string(i)] = fcn_despacho_PNL(;Pd=PdVect[i],aTx=aTx,TIPO_SOLVER=TIPO_SOLVER,
                                            cg=cg,Pmax=Pmax,Pmin=Pmin,
                                            index_P=index_P,index_constraints=index_constraints)
    resultPL[string(i)]  = fcn_despacho_PL(;Pd=PdVect[i],TIPO_SOLVER=TIPO_SOLVER,
                                            cg=cg,Pmax=Pmax,Pmin=Pmin,
                                            index_P=index_P,index_constraints=index_constraints)
    
    for j in 1:ng
        resultPNL[string(i)][string(j)]=Dict()
        aux1=fcn_costo_gen_balance_L(;p=resultPNL[string(i)]["Pg"][j],
                                    cgCostos=[0 cg[j] 0],cmg=resultPNL[string(i)]["cmg"]);
        resultPNL[string(i)][string(j)] = aux1;
        resultPL[string(i)][string(j)]=Dict()
        aux1=fcn_costo_gen_balance_L(;p=resultPL[string(i)]["Pg"][j],
                                    cgCostos=[0 cg[j] 0],cmg=resultPL[string(i)]["cmg"]);
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


###########################################
# Comparacion lineal
# Es sin pérdidas
###########################################

CASO = 1
resultPL[string(CASO)]["Pg"]
resultPL[string(CASO)]["ct"]
resultPL[string(CASO)]["cmg"]
resultPL[string(CASO)]["dualPmax"]
resultPL[string(CASO)]["dualPmin"]
resultPL[string(CASO)]["1"]
resultPL[string(CASO)]["2"]


###########################################
# Comparacion caso lineal y no lineal
# Si los costos marginales cambian por barra, impactará en ganancias del generador y ayuda definir en dónde instalarse para generar.
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


#PgCaso1_PNL=sum(resultPNL[string(CASO)]["Pg"])
#PgCaso1_PL=sum(resultPL[string(CASO)]["Pg"])

#DeltaCT = resultPNL[string(CASO)]["ct"]-resultPL[string(CASO)]["ct"] 
#valorUnitario = DeltaCT/(PgCaso1_PNL-PgCaso1_PL)
