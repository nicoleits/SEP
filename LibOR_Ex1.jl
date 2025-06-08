# Lista de package que se usaran
using JuMP
using GLPK
#using Gurobi
using Plots
using DataFrames

TIPO_DE_OPTIMIZADOR = 1

######################################################################################
# METODO UNO DE DEFINICION DE PROBLEMA DE OPTIMIZACION
######################################################################################

# Define modelo 
if TIPO_DE_OPTIMIZADOR == 1 
    m = Model(GLPK.Optimizer)
elseif TIPO_DE_OPTIMIZADOR==2
    m = Model(Gurobi.Optimizer)
        
end

typeof(m)

# Declara variables de decision
@variable(m,0<=x1<=10)
@variable(m,x2>=0)
@variable(m,x3>=0)
# Define función objetivo
@objective(m, Max,x1+2*x2+5*x3)

# Define restricciones del problema 
@constraint(m, constraint1, -x1+x2+3*x3<=-5)
@constraint(m, constraint2, x1+3*x2-7*x3<=10)

print(m)

optimize!(m)

# Imprime solución
println("Solucion optima:")
println("x1 = ", value(x1))
println("x2 = ", value(x2))
println("x3 = ", value(x3))
println("Funcion objetivo = ", objective_value(m))

println("Dual Variables:")
println("dual1 = ", shadow_price(constraint1))
println("dual2 = ", shadow_price(constraint2))


################################################################
# MANERAS ALTERNATIVAS DE ESCRIBIR UN PROBLEMA PL 
################################################################
# ALTERNATIVA 1
# Define variable con el modelo
m = Model(GLPK.Optimizer)

# Define variable 
@variable(m,x[1:3]>=0)
c= [1 2 5]
@objective(m, Max,sum(c[i]*x[i] for i in 1:3))

A = [-1  1  3;
      1  3 -7]
b = [-5; 10]

@constraint(m, constraint[j in 1:2], sum(A[j,i]*x[i] for i in 1:3) <= b[j])
@constraint(m, bound, x[1] <= 10)
optimize!(m)
println("Optimal Solutions:")
for i in 1:3
  println("x[$i] = ", value(x[i]))
end
# otra manera 
value.(x)
objective_value(m)
println("Dual Variables:")
for j in 1:2
  println("dual[$j] = ", shadow_price(constraint[j]))
end


# ALTERNATIVA 2
# Define variable con el modelo

m = Model(GLPK.Optimizer)

c = [ 1; 2; 5]
A = [-1  1  3;
      1  3 -7]
b = [-5; 10]

index_x = 1:3
index_constraints = 1:2

@variable(m, x[index_x] >= 0)
@objective(m, Max, sum( c[i]*x[i] for i in index_x) )

@constraint(m, constraint[j in index_constraints],
               sum( A[j,i]*x[i] for i in index_x ) <= b[j] )

@constraint(m, bound, x[1] <= 10)

JuMP.optimize!(m)

println("Optimal Solutions:")
for i in index_x
  println("x[$i] = ", JuMP.value(x[i]))
end

println("Dual Variables:")
for j in index_constraints
  println("dual[$j] = ", JuMP.shadow_price(constraint[j]))
end




