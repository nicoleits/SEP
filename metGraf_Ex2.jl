# PROBLEMA SOLUCIONADO DE MANERA GRAFICA
# Miniminzacion
using JuMP
using GLPK
#using Gurobi
using Plots
using DataFrames


m = Model(GLPK.Optimizer)
# Declara variables de decision
@variable(m,x1>=0)
@variable(m,x2>=0)

# Define función objetivo
@objective(m, Min,0.3*x1+0.9*x2)
# Define restricciones del problema 
@constraint(m, constraint1, x1+x2>=800.0)
@constraint(m, constraint2, 0.21*x1-0.3*x2<=0.0)
@constraint(m, constraint3, 0.03*x1-0.01*x2>=0.0)

print(m)
# Optimiza 
optimize!(m)

# Imprime solución
println("Solucion optima:")
println("x1 = ", value(x1))
println("x2 = ", value(x2))
println("Funcion objetivo = ", objective_value(m))

println("Dual Variables:")
println("dual1 = ", shadow_price(constraint1))
println("dual2 = ", shadow_price(constraint2))


