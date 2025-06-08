# Lista de package que se usaran
using JuMP
using GLPK
using HiGHS
using Ipopt
using Plots
using DataFrames
#using Gurobi

TIPO_SOLVER = 1; # 1 = HiGHS, 2 = Gurobi, 3= Ipopt ; 4 = Pajarito
pmax = [600 400 200]
pmin = [150 100 50]
cg   = [7.2 7.85 7.97]

ng = 3;
pd = 500:50:1200;
nT = length(pd)

## Crea variable con modelo de optimizacións
if TIPO_SOLVER==1
    m = Model(HiGHS.Optimizer)
#    set_attribute(m, "presolve", "on")
#    set_attribute(m, "time_limit", 60.0)
elseif TIPO_SOLVER==2
    m = Model(Gurobi.Optimizer)
elseif TIPO_SOLVER==3
    m = Model(Ipopt.Optimizer)

end
# Define variables de decisión
@variable(m,pg[1:ng,1:nT])
@variable(m,ug[1:ng,1:nT], Bin)

# Función objetivo
@objective(m, Min, sum(sum( cg[i]*pg[i,j]  for i in 1:ng) for j in 1:nT ))
#@objective(m, Min, sum( cg1[i]+cg2[i]*pg[i]  for i in 1:ng) )
#@objective(m, Min, sum( cg1[i]+cg2[i]*pg[i]+cg3[i]*pg[i]^2  for i in 1:ng) )

# Define restricciones
@constraint(m, balance[j=1:nT], sum(pg[:,j]) == pd[j])
@constraint(m, PmaxConst[i in 1:ng, j in 1:nT], pg[i,j]<=pmax[i]*ug[i,j])
@constraint(m, PminConst[i in 1:ng,j in 1:nT], pg[i,j]>=pmin[i]*ug[i,j])

print(m)
optimize!(m)

result = Dict()
result["Pg"] = value.(pg);
result["ug"] = value.(ug);
result["ct"] = objective_value(m);
result["cmg"] = dual.(balance);
result["dualPmax"] = dual.(PmaxConst);
result["dualPmin"] = dual.(PminConst);
println("Los resultados del problema se muestran a continuación")
result 

transpose(result["Pg"])
transpose(result["ug"])

################################################################
# ENCUENTRA COSTO MARGINALES
################################################################

solution_summary(m)
# El costo marginal no está definido para problemas lineales enteros mixtos
# por esa razón, es necesario correr el despacho para la hora en cuestion

ugSol = value.(ug)
fix.(ug,ugSol;force =true)
# Se indica que la variable ug deja de ser binaria
unset_binary.(ug)
print(m)

optimize!(m)
dual_status(m)

result["Pg"] = value.(pg);
result["ug"] = value.(ug);
result["ct"] = objective_value(m);
result["cmg"] = dual.(balance);
result["dualPmax"] = dual.(PmaxConst);
result["dualPmin"] = dual.(PminConst);
println("Los resultados del problema se muestran a continuación")
result 


result["cmg"]