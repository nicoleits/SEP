# Lista de package que se usaran
using JuMP
using GLPK
using HiGHS
#using Gurobi
using Plots
using DataFrames
# Problema de despacho económico sin saturación de restricciones

# Datos del problema
index_P = 1:2
index_constraints = 1
Pmax = [100 150]
Pmin = [0 80]
cg   = [30 70]
Pd = 170.0

## Modelo de optimizacións
m = Model(HiGHS.Optimizer)
# Define variables de decisión 
@variable(m,P[index_P]>=0)
# Define función objetivo
@objective(m, Min, sum( cg[i]*P[i] for i in index_P) )
# Define restricciones
@constraint(m, balance, sum(P) == Pd) #multiplicador de lagrange (valor dual) requiere nombre, en este caso "balance"
@constraint(m, PmaxConst[i in index_P], P[i]<=Pmax[i])
@constraint(m, PminConst[i in index_P], P[i]>=Pmin[i])

print(m)
optimize!(m)

println("El despacho económico es:")
println(value.(P))
println( "Costo total de operación = ",objective_value(m))
println( "Valor dual = ", dual(balance))
println("Valor dual balance =", shadow_price(balance))
println("Valor dual Pmax", dual.(PmaxConst))
println("Valor dual Pmax", shadow_price.(PmaxConst))