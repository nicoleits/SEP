# PROBLEMA SOLUCIONADO DE MANERA GRAFICA
using JuMP
using GLPK
using HiGHS
#using Gurobi
using Plots
using DataFrames

# Define variable tipo modelo de optimización
m = Model(HiGHS.Optimizer)
# Declara variables de decision
@variable(m,x1>=0)
@variable(m,x2>=0)

# Define función objetivo
@objective(m, Max,5*x1+4*x2) #Min si quieres minimizar la funcion
# Define restricciones del problema 
@constraint(m, constraint1, 6*x1+4*x2<=24)
@constraint(m, constraint2, x1+2*x2<=6)
@constraint(m, constraint3, -x1+x2<=1)
@constraint(m, constraint4, x2<=2)

print(m)
# Optimiza 
optimize!(m)
status = termination_status(m) # Si es optima debe aparecer un 1
# Imprime solución
println("Solucion optima:")
println("x1 = ", value(x1))
println("x2 = ", value(x2))
println("Funcion objetivo = ", objective_value(m))


println("Dual Variables:")
println("dual1 = ", shadow_price(constraint1))
println("dual2 = ", shadow_price(constraint2))


########################################################################
# Analisis de sensibilidad 
c1_vect= [6 4 5]
c2_vect= [4 2 4]

function modelolineal(;c1=1,c2=2)
    # Define variable con info de modelo
    m = Model(GLPK.Optimizer)
    # Declara variables de decision
    @variable(m,x1>=0)
    @variable(m,x2>=0)
    
    # Define función objetivo
    @objective(m, Max,c1*x1+c2*x2)
    # Define restricciones del problema 
    @constraint(m, constraint1, 6*x1+4*x2<=24)
    @constraint(m, constraint2, x1+2*x2<=6)
    @constraint(m, constraint3, -x1+x2<=1)
    @constraint(m, constraint4, x2<=2)
    
    #print(m)
    # Optimiza 
    optimize!(m)
    
    # Imprime solución
    #println("Solucion optima:")
    #println("x1 = ", value(x1))
    #println("x2 = ", value(x2))
    #println("Funcion objetivo = ", objective_value(m))
    
    #println("Dual Variables:")
    #println("dual1 = ", shadow_price(constraint1))
    #println("dual2 = ", shadow_price(constraint2))
    result = Dict()
    result["x1"] = value(x1);
    result["x2"] = value(x2);
    result["Objetivo"] = objective_value(m);
    result["dual1"] = shadow_price(constraint1);
    result["dual2"] = shadow_price(constraint2);
    return result

end    


result_1 = modelolineal(;c1=c1_vect[1],c2=c2_vect[1])
a= result_1["x1"]
result_1["Objetivo"]
keys(result_1)

result_2 = modelolineal(;c1=c1_vect[2],c2=c2_vect[2])
result_3 = modelolineal(;c1=c1_vect[3],c2=c2_vect[3])
##########################################################################
# Ciclo for
resultTodos = Dict()
n = length(c1_vect) # number

for i in 1:n
    resultTodos[string(i)] = modelolineal(;c1=c1_vect[i],c2=c2_vect[i])


end
resultTodos["1"]
resultTodos["2"]
keys(resultTodos)
resultTodos["1"]["x1"]
resultTodos["1"]["x2"]
########################################################################
# Lectura de constantes desde excel 
using XLSX
dataExcel = XLSX.readdata("2024_04_01_datos.xlsx","Hoja1","A2:B4")
c1_vect = dataExcel[:,1]
c2_vect = dataExcel[:,2]


resultTodos = Dict()
n = length(c1_vect) # number

for i in 1:n
    resultTodos[string(i)] = modelolineal(;c1=c1_vect[i],c2=c2_vect[i])


end
resultTodos["1"]
resultTodos["2"]
resultTodos["3"]

xf = XLSX.readxlsx("2024_04_01_datos.xlsx")
xf["Hoja1!A2:B4"]

xf[1]

XLSX.openxlsx("2024_04_01_datos.xlsx",mode="rw") do xf
 sheet =xf[1]
 sheet["D2"] = 3 
end


