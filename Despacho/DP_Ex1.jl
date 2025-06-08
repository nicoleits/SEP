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
Pmin = [0 0]
cg   = [30 70]
Pd = 170.0

## Modelo de optimizacións
#m = Model(GLPK.Optimizer)
m = Model(HiGHS.Optimizer)

# Define variables de decisión 
@variable(m,P[index_P]>=0)
# Define función objetivo
@objective(m, Min, sum( cg[i]*P[i] for i in index_P) )
# Define restricciones
@constraint(m, balance, sum(P) == Pd)
@constraint(m, PmaxConst[i in index_P], P[i]<=Pmax[i])
@constraint(m, PminConst[i in index_P], P[i]>=Pmin[i])

# Imprime el modelo para validar
print(m)
optimize!(m)

println("El despacho económico es:")
println(value.(P))
println( "Costo total de operación = ",objective_value(m))
println( "Valor dual balance = ", dual(balance))
println( "Valor dual balance= ", shadow_price(balance))
println( "Valor dual Pmax = ", dual.(PmaxConst))
println( "Valor dual Pmax = ", shadow_price.(PmaxConst))



####################################################################
# Modifica la demanda en un mega, de 170 a 171
####################################################################


Pmax = [100 150]
Pmin = [0 0]
cg   = [30 70]
Pd = 171.0

## Modelo de optimizacións
m = Model(HiGHS.Optimizer)
# Define variables de decisión 
@variable(m,P[index_P]>=0)
# Define función objetivo
@objective(m, Min, sum( cg[i]*P[i] for i in index_P) )
# Define restricciones
@constraint(m, balance, sum(P) == Pd)
@constraint(m, PmaxConst[i in index_P], P[i]<=Pmax[i])
@constraint(m, PminConst[i in index_P], P[i]>=Pmin[i])

optimize!(m)

println( "Costo total de operación = ",objective_value(m))
println( "Valor dual balance = ", dual(balance))
println( "Valor dual balance= ", shadow_price(balance))
println( "Valor dual Pmax = ", dual.(PmaxConst))
println( "Valor dual Pmax = ", shadow_price.(PmaxConst))

####################################################################
# Modifica la demanda Pmax de la central más barata
####################################################################

Pmax = [101 150]
Pmin = [0 0]
cg   = [30 70]
Pd = 170.0

## Modelo de optimizacións
m = Model(HiGHS.Optimizer)
# Define variables de decisión 
@variable(m,P[index_P]>=0)
# Define función objetivo
@objective(m, Min, sum( cg[i]*P[i] for i in index_P) )
# Define restricciones
@constraint(m, balance, sum(P) == Pd)
@constraint(m, PmaxConst[i in index_P], P[i]<=Pmax[i])
@constraint(m, PminConst[i in index_P], P[i]>=Pmin[i])

optimize!(m)

println( "Costo total de operación = ",objective_value(m))
println("El despacho:", value.(P))
println( "Valor dual balance = ", dual(balance))
println( "Valor dual balance= ", shadow_price(balance))
println( "Valor dual Pmax = ", dual.(PmaxConst))
println( "Valor dual Pmax = ", shadow_price.(PmaxConst))

