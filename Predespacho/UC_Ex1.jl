# Lista de package que se usaran
#Problema de dada una demanda, que generadores se prenden y cuanto generan.
#Se ingresa una variable discreta para cada generador, que indica si está prendido o apagado. Pero.
# Es un problema no convexo, por lo que se debe usar un solver no convexo.
using JuMP
using GLPK
using HiGHS
using Ipopt
using Plots
using DataFrames
#using Gurobi
#using Pajarito
#using Hypatia 

TIPO_SOLVER = 1; # 1 = HiGHS, 2 = Gurobi, 3= Ipopt ; 
pmax = [600 400 200]
pmin = [150 100 50]
#cg1   = [510*1.1 310 78*1.2]
cg   = [7.2 7.85 7.97] #costos variables de cada generador
#cg3   = [0.00142*1.1 0.00194 0.00482*1.2] # Valido con Gurobi

ng = 3;
pd = 550;


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
@variable(m,pg[1:ng]) #potencia generada por cada generador (despacho de cada unidad)
@variable(m,ug[i=1:ng], Bin) #variable binaria que indica si el generador i está prendido (1) o apagado (0)

# Función objetivo
@objective(m, Min, sum( cg[i]*pg[i]  for i in 1:ng) ) #Minimizar el costo de generación
#@objective(m, Min, sum( cg1[i]+cg2[i]*pg[i]  for i in 1:ng) )
#@objective(m, Min, sum( cg1[i]+cg2[i]*pg[i]+cg3[i]*pg[i]^2  for i in 1:ng) )

# Define restricciones
@constraint(m, balance, sum(pg) == pd)
@constraint(m, PmaxConst[i in 1:ng], pg[i]<=pmax[i]*ug[i])
@constraint(m, PminConst[i in 1:ng], pg[i]>=pmin[i]*ug[i])

print(m)
optimize!(m)

result = Dict()
result["Pg"] = value.(pg);
result["ug"] = value.(ug);
result["ct"] = objective_value(m);
result["cmg"] = dual(balance);
result["dualPmax"] = dual.(PmaxConst);
result["dualPmin"] = dual.(PminConst);
println("Los resultados del problema se muestran a continuación")
result 

# se definio variable dual para cada restricción. Pero el problema es que el costo marginal no está definido para problemas lineales enteros mixtos


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
result["cmg"] = dual(balance);
result["dualPmax"] = dual.(PmaxConst);
result["dualPmin"] = dual.(PminConst);
println("Los resultados del problema se muestran a continuación")
result 

# Cuando quiero calcular una variable dual de alguna restriccion, 
#no puedo usar la variable dual asociada a un modelo que tenga una variable discreta