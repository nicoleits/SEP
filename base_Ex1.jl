# Define variables y revisa el tipo de variable
a= 1
b= 2.0
c= a+b
typeof(a)
typeof(b)
typeof(c)

#numeros complejos
d = c+a*im
abs(d)
angle(d)
real(d)
imag(d)

# se limpia el terminal REPL ctrl+l
# imprime resultados 
println("Hola, la variable a es:")
println(a)
println("Hola la variable a= $a")
println("Hola la variable b= $b")

# Operaciones con matrices
a= [1 2 3;4 5 6;9 9 7]
b = [1 2 3;4 5 6;10 11 12]
c = a*b
d = a+b

a[1,1]
a[1,3]
a[:,3]
a[1,:]
a[:,1]

# determinante
using LinearAlgebra
det(a)
# transpuesta de una matriz
a
transpose(a)
# autovalores 
eigvals(a)
# Creación de vectores 
a=1:0.5:10
length(a)
typeof(a)
for i in a
    println(i)
end

a=zeros(2,3)
a=ones(2,3)
a = Diagonal(ones(2))
a = LinRange(0,1.1,100)

#Comentarios sobre notación dot "."
a = rand(3)
#a+3.0 #Error
a.+3.0 #correcto
#sin(a)
sin.(a)

# grafica 
using Plots 

x = LinRange(0,2*pi, 200)
y = cos.(x)

# Graficar los datos
plt=plot(x, y, 
    xlabel = "Eje X",    # Nombre del eje X
    ylabel = "Eje Y",    # Nombre del eje Y
    title = "Gráfico de ejemplo",  # Título del gráfico
    label = "Datos",     # Etiqueta de los datos (aparecerá en la leyenda)
    legend = :bottomright)  # Posición de la leyenda

# Mostrar la gráfica
display(plt)
## Agrega limites

x = LinRange(0,2*pi, 200)
y = cos.(x)
xlims = (0, pi/2)  # Límites para el eje X
ylims = (-1, 1)   # Límites para el eje Y
typeof(xlims)
# Graficar los datos
plt=plot(x, y, 
    xlabel = "Eje X",    # Nombre del eje X
    ylabel = "Eje Y",    # Nombre del eje Y
    title = "Gráfico de ejemplo",  # Título del gráfico
    label = "Datos",     # Etiqueta de los datos (aparecerá en la leyenda)
    legend = :bottomright,
    xlims = xlims,
    ylims = ylims)  # Posición de la leyenda

# Mostrar la gráfica
display(plt)


## condicionales
a= 300

if a==2
    println("a es: $a")
elseif a==1
    println("a es 1, a = $a")
else 
    println("a no es nada, a = $a")
end


function primeraFuncion(x)
   y = x+1;
   println(y)
   return y

end

a = primeraFuncion(2);




