# Ejemplo de tres barras, modelo detallado
# La red de estudio es sintética. Se creo para implementar modelos de stochastic UC durante mis estudios de posgrado
using JuMP
using HiGHS
#using Ipopt
using Plots
using DataFrames
using XLSX
using LinearAlgebra
################################################################
# CONFIGURACION DEL PROBLEMA
################################################################
TIPO_CASO_CON_SIN_ER        = 0;
# 1: Escoge archivo UC_datEx8.xlsx en donde considera perfil de renovables
# 0: Escoge archivo UC_datEx8_sinER.xlsx en donde considera perfil de renovables
TIPO_SOLVER             = 1; # 1 = HiGHS, 2 = Gurobi, 3= Ipopt 
TIPO_SERIE_ERV          = 9; 
                        #1: WT1 y WT2 perfil 1
                        #2: WT1 y WT2 perfil 2
                        #3: WT1 y WT2 perfil 3
                        #4: PV1 y PV2 perfil 1
                        #5: PV1 y PV2 perfil 2
                        #6: PV1 y PV2 perfil 3
                        #7: PV1 y WT2 perfil 1
                        #8: PV1 y WT2 perfil 2
                        #9: PV1 y WT2 perfil 3
## Escoge nombre de archivo de lectura de datos
if TIPO_CASO_CON_SIN_ER ==0
    NOMBRE_ARCHIVO_DATOS    ="Predespacho/UC_datEx8_sinER.xlsx"; 
elseif TIPO_CASO_CON_SIN_ER ==1
    NOMBRE_ARCHIVO_DATOS    ="Predespacho/UC_datEx8.xlsx"; 
end
sB                  = 100; 
################################################################
# LEE DATOS 
################################################################
# Datos red
if TIPO_CASO_CON_SIN_ER==0 # sin energia renovable
    datGen      =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"Gen!C4:O12")
    datDem      =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"dem!A4:J27")
    datLineas   =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"Lineas!A4:G14")

elseif TIPO_CASO_CON_SIN_ER==1 # con Energia renovable
    datGen      =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"Gen!C4:O14")
    datDem      =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"dem!A4:J27")
    datLineas   =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"Lineas!A4:G14")
    
    # lee datos de perfiles de energía renovable
    if TIPO_SERIE_ERV==1
        datEr       =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"ERV!C5:AB6")

    elseif TIPO_SERIE_ERV==2
        datEr       =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"ERV!C13:AB14")

    elseif TIPO_SERIE_ERV==3
        datEr       =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"ERV!C20:AB21")
    elseif TIPO_SERIE_ERV==4 # solar
        datEr       =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"ERV!C27:AB28")
    elseif TIPO_SERIE_ERV==5
        datEr       =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"ERV!C35:AB36")
    elseif TIPO_SERIE_ERV==6
        datEr       =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"ERV!C42:AB43")
    elseif TIPO_SERIE_ERV==7
        datEr       =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"ERV!C49:AB50")
    elseif TIPO_SERIE_ERV==8
        datEr       =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"ERV!C56:AB57")
    elseif TIPO_SERIE_ERV==9
        datEr       =   XLSX.readdata(NOMBRE_ARCHIVO_DATOS,"ERV!C63:AB64")

    end

end
datEr

################################################################
# PARAMETROS DE LA RED BAJO ESTUDIO
################################################################

busGen  = datGen[:,1]
cv      = datGen[:,2]
cEnc    = datGen[:,3]
cApa    = datGen[:,4]
pmax    = datGen[:,5]
pmin    = datGen[:,6]
t_up    = datGen[:,7]
t_do    = datGen[:,8]
R_up    = datGen[:,9]
R_do    = datGen[:,10]
tipoGen = datGen[:,11]
aportaReserva       = datGen[:,12]
kReserva            = datGen[:,13] # % de reserva potencia total


pd     =  datDem[:,2:end] # Demanda en barra 3
horasDia = datDem[:,1]
Tmax    = datLineas[:,5]
xij     = datLineas[:,4]
fromTx  = datLineas[:,2]
toTx    = datLineas[:,3]


# Crea variable pEr cuando el caso considera renovable 
if TIPO_CASO_CON_SIN_ER==1 && TIPO_SERIE_ERV>=1
        pEr    = datEr[:,3:end]'
end
################################################################
# CALCULOS INICIALES 
################################################################
ng  = length(cv)
nTx = length(Tmax)
nT  = length(pd[:,1])
nBus = maximum(datLineas[:,[2,3]])

################################################################
# Construye matrices A, Ag, Ad para escribir ecuaciones de balance
################################################################
# Matriz de incidencia asociada a los flujos de las lineas de transmision
A = zeros(nBus,nTx)
for k in 1:nTx
    A[toTx[k],k]= -1;
    A[fromTx[k],k]= 1;
        
end
A
# Matriz de incidencia asociado a generadores
Ag = zeros(nBus,ng)
for k in 1:ng
     Ag[busGen[k],k]=1

end
Ag

Ad = Matrix(Diagonal(ones(nBus)))
################################################################
# Construye matriz Y
################################################################
# La matriz permite la construcción de ecuaciones
Y = Matrix(Diagonal(1.0./xij))
################################################################
# MODELO UC
################################################################
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
@variable(m,pg[1:ng,1:nT]) # potencia generador
@variable(m,rg[1:ng,1:nT]) # reserva
@variable(m,fTx[1:nTx,1:nT]) # flujo
@variable(m,theta[1:nBus,1:nT]) # theta

@variable(m,ug[1:ng,1:nT], Bin)
@variable(m,uEnc[1:ng,1:nT], Bin)
@variable(m,uApa[1:ng,1:nT], Bin)

# Función objetivo
@objective(m, Min, sum(sum( cv[i]*pg[i,j] +cEnc[i]*uEnc[i,j]+cApa[i]*uApa[i,j] for i in 1:ng) for j in 1:nT ))


# Balance
@constraint(m,balance[j in 1:nT], Ag*pg[:,j].-A*fTx[:,j] .== Ad*pd[j,:])
# restricción de flujo
# Datos xij en OHM
@constraint(m,flujoTx[j=1:nT],fTx[:,j] .== Y*A'*theta[:,j])

# Restricciones de límites máximos
# Se asume que las centrales ERV no pueden dar reservas
#tipoGen
iter=0;
for i in 1:ng
    global iter
    if tipoGen[i]==2
        iter=iter+1
        @constraint(m, [j in 1:nT], pg[i,j]+rg[i,j]<=pEr[j,iter]*ug[i,j])
        @constraint(m, [j in 1:nT], pg[i,j]>=pmin[i]*ug[i,j])
        @constraint(m, [j in 1:nT], rg[i,j]==0)
    else
        @constraint(m, [j in 1:nT], pg[i,j]+rg[i,j]<=pmax[i]*ug[i,j])
        @constraint(m, [j in 1:nT], pg[i,j]>=pmin[i]*ug[i,j])
    end

end



# limites sistema de transmision
@constraint(m, [i=1:nTx,j=1:nT],fTx[i,j]<=Tmax[i])
@constraint(m, [i=1:nTx,j=1:nT],fTx[i,j]>=-Tmax[i])

# Ecuaciones de reserva fija para cada generador en commitment 
# Nota: esta ecuación representa una manera de representar la reserva. Se considera un valor fijo
#aportaReserva 
for i in 1:ng
    if aportaReserva[i]==1
    @constraint(m,[j in 1:nT],rg[i,j]>=kReserva[i]*pmax[i]*ug[i,j])
    end
end
# Restricciones de subida y bajada. No considera el estado inicial.
# restricciones de rampa de subida
@constraint(m,ramp_up[i in 1:ng,j in 2:nT], pg[i,j]-pg[i,j-1]+rg[i,j] <= R_up[i])
# restricciones de rampa de bajada
@constraint(m,ramp_dw[i in 1:ng,j in 2:nT], pg[i,j]-pg[i,j-1] >= -R_do[i])

# Restricciones de tiempos mínimo de encendido y apagado
# para el t=1 se calcula un despacho
@constraint(m, [i in 1:ng],ug[i,1] == uEnc[i,1]-uApa[i,1])
@constraint(m, [i in 1:ng],ug[i,1] >= uEnc[i,1])
@constraint(m, [i in 1:ng],1-ug[i,1] >= uApa[i,1])

# para instantes de tiempo mayor a 1
@constraint(m, [i in 1:ng,j in 2:nT], ug[i,j] == ug[i,j-1] + uEnc[i,j]-uApa[i,j] )

# Tiempos minimos de operación y apagado
# Tiempos minimos de operacion 
for i in 1:ng
    rang1= t_up[i]:nT
    for j in rang1
        rang2 = (j-t_up[i]+1):j
        @constraint(m, ug[i,j] >= sum(uEnc[i,k] for k in rang2))
    end
end
# restricciones para tiempos menores a t_up
@constraint(m,[i in 1:ng,j in 2:t_up[i]],ug[i,j] >= sum(uEnc[i,k] for k in 1:j))
# Tiempos minimos de apagado
for i in 1:ng
    rang1= t_do[i]:nT
    for j in rang1
        rang2 = (j-t_do[i]+1):j
        @constraint(m, 1-ug[i,j] >= sum(uApa[i,k] for k in rang2))
    end
end
@constraint(m,[i in 1:ng,j in 2:t_do[i]],1-ug[i,j] >= sum(uApa[i,k] for k in 1:j))


#print(m)
optimize!(m)


ugSol = value.(ug)
uEncSol = value.(uEnc)
uApaSol = value.(uApa)
fix.(ug,ugSol;force =true)
fix.(uEnc,uEncSol;force =true)
fix.(uApa,uApaSol;force =true)
# Se indica que la variable ug deja de ser binaria
unset_binary.(ug)
unset_binary.(uEnc)
unset_binary.(uApa)

#print(m)

optimize!(m)
dual_status(m)

result2 = Dict()
result2["Pg"] = value.(pg);
result2["Rg"] = value.(rg);
result2["ug"] = value.(ug);
result2["fij"] = value.(fTx);
result2["ct"] = objective_value(m);

# Guarda costos marginales 
aux=zeros(nBus,nT)
for i in 1:nT
    aux[:,i] = dual.(balance[i]);
    
end
result2["cmg"] = aux

println("Los resultados del problema se muestran a continuación")
result2 
result2["cmg"] 
result2["ug"]
################################################################
# PEGA RESULTADOS EN excel
################################################################
xf = XLSX.readxlsx(NOMBRE_ARCHIVO_DATOS)
xf[1]
xf[9]
xf[8]



XLSX.openxlsx(NOMBRE_ARCHIVO_DATOS,mode="rw") do xf
 sheet =xf[5]
 #sheet["A1"] = ["pg1", "pg2", "pg3"]  
 aux =result2["Pg"]
 sheet["C4"] = aux;
 sheet =xf[6]
 #sheet["A1"] = ["pg1", "pg2", "pg3"]  
 aux =result2["Rg"]
 sheet["C4"] = aux;

 sheet =xf[7]
 aux =result2["fij"]
 sheet["E4"] = aux;

 sheet =xf[8]
 aux =result2["ug"]
 sheet["C4"] = aux;
 
 sheet =xf[9]
 aux =result2["cmg"]
 sheet["C4"] = aux;
 
end



###############################################################
# Algunas gráficas
###############################################################

# Demanda agregada
x= horasDia;
y=zeros(nT,1)
for i in 1:nT
 y[i,1]=sum(pd[i,:]);
end

plt=plot(x, y, 
    xlabel = "Tiempo [h]",    # Nombre del eje X
    ylabel = "Potencia [MW]",    # Nombre del eje Y
    title = "Demanda agregada",  # Título del gráfico
    label = "pd",     # Etiqueta de los datos (aparecerá en la leyenda)
    linewidth=3
    #legend = :bottomright)  # Posición de la leyenda
    )
# Mostrar la gráfica
display(plt)
savefig("myplot.png")      # saves the CURRENT_PLOT as a .png
savefig(plt, "myplot.pdf")  

# Grafica potencia generada
x= horasDia;
y= result2["Pg"]'
plt=areaplot(x, y, 
    xlabel = "Tiempo [h]",    # Nombre del eje X
    ylabel = "Potencia generada [MW]",    # Nombre del eje Y
    title = "Despacho",  # Título del gráfico
    label = ["pg1" "pg2" "pg3" "pg4" "pg5" "pg6" "pg7" "pg8" "pg9" "pg10" "pg11"],     # Etiqueta de los datos (aparecerá en la leyenda)
    linewidth=0,
    #serie =["y4"]
    #legend = :bottomright)  # Posición de la leyenda
    )
# Mostrar la gráfica
display(plt)
savefig("despachoi.png")      # saves the CURRENT_PLOT as a .png
savefig(plt, "despacho.pdf")  

# Grafica potencia generada
x= horasDia;
y= result2["Pg"]'
plt=plot(x, y, 
    xlabel = "Tiempo [h]",    # Nombre del eje X
    ylabel = "Potencia generada [MW]",    # Nombre del eje Y
    title = "Despacho",  # Título del gráfico
    label = ["pg1" "pg2" "pg3" "pg4" "pg5" "pg6" "pg7" "pg8" "pg9" "pg10" "pg11"],     # Etiqueta de los datos (aparecerá en la leyenda)
    linewidth=1.2,
    #serie =["y4"]
    #legend = :bottomright)  # Posición de la leyenda
    )
# Mostrar la gráfica
display(plt)
savefig("despachoi.png")      # saves the CURRENT_PLOT as a .png
savefig(plt, "despacho.pdf")  


# Grafica potencia generada
x= horasDia;
y= result2["ug"]'
typeof(y)
plt=plot(x, y, 
    xlabel = "Tiempo [h]",    # Nombre del eje X
    ylabel = "Encendido",    # Nombre del eje Y
    title = "Predespacho",  # Título del gráfico
    label = ["ug1" "ug2" "ug3" "ug4" "ug5" "ug6" "ug7" "ug8" "ug9" "ug10" "ug11"],     # Etiqueta de los datos (aparecerá en la leyenda)
    
    linewidth=3,
    #serie =["y4"]
    #legend = :bottomright)  # Posición de la leyenda
    )
# Mostrar la gráfica
display(plt)
savefig("despachoi.png")      # saves the CURRENT_PLOT as a .png
savefig(plt, "despacho.pdf")  




# Grafica de potencia renovable
if TIPO_CASO_CON_SIN_ER==1
x= horasDia;
y= pEr;
y
typeof(y)

plt=plot(x, y[:,1], 
    xlabel = "Tiempo [h]",    # Nombre del eje X
    ylabel = "potencia [MW]",    # Nombre del eje Y
    title = "Predespacho",  # Título del gráfico
    label = ["Pw1"],     # Etiqueta de los datos (aparecerá en la leyenda)
    
    linewidth=3,
    #serie =["y4"]
    #legend = :bottomright)  # Posición de la leyenda
    )

    plot!(x, y[:,2], 
    xlabel = "Tiempo [h]",    # Nombre del eje X
    ylabel = "potencia [MW]",    # Nombre del eje Y
    title = "Predespacho",  # Título del gráfico
    label = ["Pw2"],     # Etiqueta de los datos (aparecerá en la leyenda)
    
    linewidth=3,
    #serie =["y4"]
    #legend = :bottomright)  # Posición de la leyenda
    )

# Mostrar la gráfica
display(plt)
savefig("pw.png")      # saves the CURRENT_PLOT as a .png
savefig(plt, "pw.pdf")  
end


