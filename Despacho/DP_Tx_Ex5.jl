
# Carga paquetes de julia que serán usados
using JuMP
#using GLPK
using HiGHS
#using Gurobi
#using Ipopt
using Plots
#using DataFrames
using XLSX
# Problema de despacho económico de carga considerando transmision
##################################################################
# DATOS DEL PROBLEMA 
##################################################################
nombre_archivo_datos = "Despacho/datos_3barras.xlsx"
dat_gen     = XLSX.readdata(nombre_archivo_datos, "gen!C5:F6")
dat_lineas  = XLSX.readdata(nombre_archivo_datos,  "lineas!B6:G8")
dat_bus     = XLSX.readdata(nombre_archivo_datos,  "bus!B6:D8")


##################################################################
# Modelo multi nodal - Base 
##################################################################

TIPO_SOLVER = 1; # 1 = HiGHS, 2 = Gurobi, 3= Ipopt 
SB          = 100; # Potencia base


ng      = length(dat_gen[:,1]) #Cantidad de generador
ntx     = length(dat_lineas[:,1]) # cantidad de lineas
nbus    = length(dat_lineas[:,1]) # cantidad de barras

cg      = dat_gen[:,2]
pmax    = dat_gen[:,4]
pmin    = dat_gen[:,3]

pd      = dat_bus[:,3]

txMax   = dat_lineas[:,6]
txMin   = -1*txMax
xij     = dat_lineas[:,5]

    
## Modelo de optimizacións
m = Model(HiGHS.Optimizer)
#set_attribute(m, "presolve", "on")
#set_attribute(m, "time_limit", 60.0)
# Define variables de decisión
@variable(m, pmin[i]<=pg[i=1:ng]<=pmax[i])
@variable(m, txMin[i]<=ftx[i=1:ntx]<=txMax[i])
@variable(m, theta[i=1:nbus])
# Define función objetivo
@objective(m, Min, sum( cg[i]*pg[i]  for i in 1:ng) )
# Define restricciones
@constraint(m, balance1, pg[1]-ftx[1]-ftx[2] == pd[1])
@constraint(m, balance2, pg[2]+ftx[1]-ftx[3] == pd[2])
@constraint(m, balance3, ftx[2]+ftx[3] == pd[3])
@constraint(m,consTx1,ftx[1]/SB==(theta[1]-theta[2])/xij[1])
@constraint(m,consTx2,ftx[2]/SB==(theta[1]-theta[3])/xij[2])
@constraint(m,consTx3,ftx[3]/SB==(theta[2]-theta[3])/xij[3])


print(m)
optimize!(m)
result = Dict();
result["Pg"] = value.(pg);
result["fTx"] = value.(ftx);
result["theta"] = value.(theta);
result["ct"] = objective_value(m);
result["cmg1"] = dual(balance1);
result["cmg2"] = dual(balance2);
result["cmg3"] = dual(balance3);
result



##################################################################
# DATOS DEL PROBLEMA - Modelo uninodal - Caso A1
##################################################################
ng      = length(dat_gen[:,1])
ntx     = length(dat_lineas[:,1])
nbus    = length(dat_lineas[:,1])

cg      = dat_gen[:,2]
pmax    = dat_gen[:,4]
pmin    = dat_gen[:,3]

pd      = dat_bus[:,3]

txMax   = dat_lineas[:,6]
txMin   = -1*txMax
xij     = dat_lineas[:,5]
rij     = dat_lineas[:,4]
 
## Modelo de optimizacións
m = Model(HiGHS.Optimizer)
# Define variables de decisión
@variable(m, pmin[i]<=pg[i=1:ng]<=pmax[i])
# Define función objetivo
@objective(m, Min, sum( cg[i]*pg[i]  for i in 1:ng) )
# Define restricciones
@constraint(m, balance1, sum(pg)== sum(pd))


print(m)
optimize!(m)
result = Dict();
result["Pg"] = value.(pg);
result["ct"] = objective_value(m);
result["cmg1"] = dual(balance1);
result
#uninodal y multinodal sin perdidas cmg iguales


##################################################################
# DATOS DEL PROBLEMA - congestion - desprendimiento de carga 
# Caso A3
##################################################################
TIPO_SOLVER = 1; # 1 = HiGHS, 2 = Gurobi, 3= Ipopt 
SB          = 100; # Potencia base

ng      = length(dat_gen[:,1])
ntx     = length(dat_lineas[:,1])
nbus    = length(dat_lineas[:,1])

cg      = [30 70]
pmax    = [100 150]
pmin    = dat_gen[:,3]

pd      = [0 0 170]

txMax   = [100 100 90]
txMin   = -1*txMax
xij     = dat_lineas[:,5]

    
## Modelo de optimizacións
m = Model(HiGHS.Optimizer)
#set_attribute(m, "presolve", "on")
#set_attribute(m, "time_limit", 60.0)
# Define variables de decisión
@variable(m, pmin[i]<=pg[i=1:ng]<=pmax[i])
@variable(m, txMin[i]<=ftx[i=1:ntx]<=txMax[i])
@variable(m, theta[i=1:nbus])
@variable(m, 0<=pr<=10000) #pr es 0, energia no podra ser suministrada al sistema

# Define función objetivo
@objective(m, Min, sum( cg[i]*pg[i]+300*pr  for i in 1:ng) )
# Define restricciones
@constraint(m, balance1, pg[1]-ftx[1]-ftx[2] == pd[1])
@constraint(m, balance2, pg[2]+ftx[1]-ftx[3] == pd[2])
@constraint(m, balance3, pr+ftx[2]+ftx[3] == pd[3])
@constraint(m,consTx1,ftx[1]/SB==(theta[1]-theta[2])/xij[1])
@constraint(m,consTx2,ftx[2]/SB==(theta[1]-theta[3])/xij[2])
@constraint(m,consTx3,ftx[3]/SB==(theta[2]-theta[3])/xij[3])


print(m)
optimize!(m)
result = Dict();
result["Pg"] = value.(pg);
result["Pr"] = value.(pr);

result["fTx"] = value.(ftx);
result["theta"] = value.(theta);
result["ct"] = objective_value(m);
result["cmg1"] = dual(balance1);
result["cmg2"] = dual(balance2);
result["cmg3"] = dual(balance3);
result


##################################################################
# DATOS DEL PROBLEMA - congestion - desprendimiento de carga 
# caso anterior, pero se eliminan restricions de LKC
# Caso A4
##################################################################
TIPO_SOLVER = 1; # 1 = HiGHS, 2 = Gurobi, 3= Ipopt 
SB          = 100; # Potencia base

ng      = length(dat_gen[:,1])
ntx     = length(dat_lineas[:,1])
nbus    = length(dat_lineas[:,1])

cg      = [30 70]
pmax    = [100 150]
pmin    = dat_gen[:,3]

pd      = [0 0 170]

txMax   = [100 100 90]
txMin   = -1*txMax
xij     = dat_lineas[:,5]

    
## Modelo de optimizacións
m = Model(HiGHS.Optimizer)
#set_attribute(m, "presolve", "on")
#set_attribute(m, "time_limit", 60.0)
# Define variables de decisión
@variable(m, pmin[i]<=pg[i=1:ng]<=pmax[i])
@variable(m, txMin[i]<=ftx[i=1:ntx]<=txMax[i])
#@variable(m, theta[i=1:nbus])
@variable(m, 0<=pr<=10000)

# Define función objetivo
@objective(m, Min, sum( cg[i]*pg[i]+300*pr  for i in 1:ng) )
# Define restricciones
@constraint(m, balance1, pg[1]-ftx[1]-ftx[2] == pd[1])
@constraint(m, balance2, pg[2]+ftx[1]-ftx[3] == pd[2])
@constraint(m, balance3, pr+ftx[2]+ftx[3] == pd[3])
#@constraint(m,consTx1,ftx[1]/SB==(theta[1]-theta[2])/xij[1])
#@constraint(m,consTx2,ftx[2]/SB==(theta[1]-theta[3])/xij[2])
#@constraint(m,consTx3,ftx[3]/SB==(theta[2]-theta[3])/xij[3])


print(m)
optimize!(m)
result = Dict();
result["Pg"] = value.(pg);
result["Pr"] = value.(pr);

result["fTx"] = value.(ftx); 
#result["theta"] = value.(theta); los thetas definen la direccion del flujo, y uno no decide su direccion, ya que estos vienen de aplicaciones físicas
# no considerar esta ecuación devuelve todo el problema a los resultados anteriores, pero esto está excluyendo condiciones de direccion importantes 
result["ct"] = objective_value(m);
result["cmg1"] = dual(balance1);
result["cmg2"] = dual(balance2);
result["cmg3"] = dual(balance3);
result







##################################################################
# Modelo multi nodal considerando un vector de restricciones
##################################################################

TIPO_SOLVER = 1; # 1 = HiGHS, 2 = Gurobi, 3= Ipopt 
SB          = 100; # Potencia base


ng      = length(dat_gen[:,1])
ntx     = length(dat_lineas[:,1])
nbus    = length(dat_lineas[:,1])

cg      = dat_gen[:,2]
pmax    = dat_gen[:,4]
pmin    = dat_gen[:,3]

pd      = dat_bus[:,3]

txMax   = dat_lineas[:,6]
txMin   = -1*txMax
xij     = dat_lineas[:,5]

    
## Modelo de optimizacións
m = Model(HiGHS.Optimizer)
#set_attribute(m, "presolve", "on")
#set_attribute(m, "time_limit", 60.0)
# Define variables de decisión
@variable(m, pmin[i]<=pg[i=1:ng]<=pmax[i])
@variable(m, txMin[i]<=ftx[i=1:ntx]<=txMax[i])
@variable(m, theta[i=1:nbus])
# Define función objetivo
@objective(m, Min, sum( cg[i]*pg[i]  for i in 1:ng) )
# Define restricciones
balance=[]
push!(balance,@constraint(m, pg[1]-ftx[1]-ftx[2] == pd[1]))
push!(balance,@constraint(m, pg[2]+ftx[1]-ftx[3] == pd[2]))
push!(balance,@constraint(m, ftx[2]+ftx[3] == pd[3]))
@constraint(m,consTx1,ftx[1]/SB==(theta[1]-theta[2])/xij[1])
@constraint(m,consTx2,ftx[2]/SB==(theta[1]-theta[3])/xij[2])
@constraint(m,consTx3,ftx[3]/SB==(theta[2]-theta[3])/xij[3])


print(m)
optimize!(m)
result = Dict();
result["Pg"] = value.(pg);
result["fTx"] = value.(ftx);
result["theta"] = value.(theta);
result["ct"] = objective_value(m);
result["cmg"] = dual.(balance)
result

