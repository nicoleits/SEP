# Lista de package que se usaran
using JuMP
using GLPK
using HiGHS
using Ipopt
using Plots
using DataFrames
using XLSX
#using Gurobi

TIPO_SOLVER = 1; # 1 = HiGHS, 2 = Gurobi, 3= Ipopt ; 4 = Pajarito
TIPO_SERIE_DEMANDA = 1; #1: CON VARIABILIDAD,0: SIN VARIABLIDAD
NOMBRE_ARCHIVO_DATOS ="Predespacho/UnitComCaso4.xlsx"; 
pmax = [500 500 500]
pmin = [30 20 1]
cg   = [50 100 150]
ng   = 3;


if TIPO_SERIE_DEMANDA==1
    dat_dem     = XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"Graf_UnitCom!B2:B25")
elseif TIPO_SERIE_DEMANDA==0
    dat_dem     = XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"Graf_UnitCom!C2:C25")

end
pd          = dat_dem[:,1]
horasDia    = 1:24

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

result1 = Dict()
result1["Pg"] = value.(pg);
result1["ug"] = value.(ug);
result1["ct"] = objective_value(m);
result1["cmg"] = dual.(balance);
result1["dualPmax"] = dual.(PmaxConst);
result1["dualPmin"] = dual.(PminConst);
println("Los resultados del problema se muestran a continuación")
result1 

transpose(result1["Pg"])
result1["Pg"]
transpose(result1["ug"])

typeof(Matrix(transpose(result1["Pg"])))
typeof(result1["Pg"])

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

result2 = Dict()
result2["Pg"] = value.(pg);
result2["ug"] = value.(ug);
result2["ct"] = objective_value(m);
result2["cmg"] = dual.(balance);
result2["dualPmax"] = dual.(PmaxConst);
result2["dualPmin"] = dual.(PminConst);
println("Los resultados del problema se muestran a continuación")
result2 

# Pega resultados en planilla excel
xf = XLSX.readxlsx(NOMBRE_ARCHIVO_DATOS)
xf[1]
xf[2]



XLSX.openxlsx(NOMBRE_ARCHIVO_DATOS,mode="rw") do xf
 sheet =xf[2]
 #sheet[""] = ["cmg"]  
 #aux =Matrix(transpose(result2["cmg"]));
 aux =reshape(result2["cmg"], length(result2["cmg"]), 1);
 sheet["K2"] = aux;

end

result2["cmg"]'

###############################################################
# Algunas gráficas
###############################################################

# Demanda
x= horasDia;
y= pd
plt=plot(x, y, 
    xlabel = "Tiempo [h]",    # Nombre del eje X
    ylabel = "Potencia [MW]",    # Nombre del eje Y
    title = "Demanda",  # Título del gráfico
    label = "pd",     # Etiqueta de los datos (aparecerá en la leyenda)
    linewidth=3
    #legend = :bottomright)  # Posición de la leyenda
    )
# Mostrar la gráfica
#display(plt)
savefig("Demanda.png")      # saves the CURRENT_PLOT as a .png
savefig(plt, "myplot.pdf")  


# Grafica potencia generada
x= horasDia;
y= result2["Pg"]'
plt=areaplot(x, y, 
    xlabel = "Tiempo [h]",    # Nombre del eje X
    ylabel = "Potencia [MW]",    # Nombre del eje Y
    title = "Despacho",  # Título del gráfico
    label = ["pc" "pg" "po"],     # Etiqueta de los datos (aparecerá en la leyenda)
    linewidth=0,
    #serie =["y4"]
    #legend = :bottomright)  # Posición de la leyenda
    )
# Mostrar la gráfica
#display(plt)
savefig("despacho.png")      # saves the CURRENT_PLOT as a .png
savefig(plt, "despacho.pdf")  


# Grafica potencia generada
x= horasDia;
y= result2["ug"]'
plt=plot(x, y, 
    xlabel = "Tiempo [h]",    # Nombre del eje X
    ylabel = "Commitment",    # Nombre del eje Y
    title = "Predespacho",  # Título del gráfico
    label = ["ugc" "ugg" "ugo"],     # Etiqueta de los datos (aparecerá en la leyenda)
    linewidth=3,
    #serie =["y4"]
    #legend = :bottomright)  # Posición de la leyenda
    )
# Mostrar la gráfica
#display(plt)
savefig("commitment.png")      # saves the CURRENT_PLOT as a .png
savefig(plt, "despacho.pdf")  







