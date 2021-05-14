# types.jl - Type definitions and structure
import Base: show, summary, convert, getindex, eltype

# Tipo abstracto para definir contenedores del IPC
abstract type AbstractCPIBase{T <: AbstractFloat} end

# Tipos para los vectores de fechas
const DATETYPE = StepRange{Date, Month}

# El tipo B representa el tipo utilizado para almacenar los índices base. 
# Puede ser un tipo flotante, por ejemplo, Float64 o bien, si los datos 
# disponibles empiezan con índices diferentes a 100, un vector, Vector{Float64}, 
# por ejemplo

"""
    FullCPIBase{T, B} <: AbstractCPIBase{T}

Contenedor completo para datos del IPC de un país. Se representa por:
- Matriz de índices de precios `ipc` que incluye la fila con los índices del númbero base. 
- Matriz de variaciones intermensuales `v`. En las filas contiene los períodos y en las columnas contiene los gastos básicos.
- Vector de ponderaciones `w` de los gastos básicos.
- Fechas correspondientes `fechas` (por meses).
"""
Base.@kwdef struct FullCPIBase{T, B} <: AbstractCPIBase{T}
    ipc::Matrix{T}
    v::Matrix{T}
    w::Vector{T}
    fechas::DATETYPE
    baseindex::B

    function FullCPIBase(ipc::Matrix{T}, v::Matrix{T}, w::Vector{T}, fechas::DATETYPE, baseindex::B) where {T, B}
        size(ipc, 2) == size(v, 2) || throw(ArgumentError("número de columnas debe coincidir entre matriz de índices y variaciones"))
        size(ipc, 2) == length(w) || throw(ArgumentError("número de columnas debe coincidir con vector de ponderaciones"))
        size(ipc, 1) == size(v, 1) == length(fechas) || throw(ArgumentError("número de filas de `ipc` debe coincidir con vector de fechas"))
        new{T, B}(ipc, v, w, fechas, baseindex)
    end
end


"""
    IndexCPIBase{T, B} <: AbstractCPIBase{T}

Contenedor genérico de índices de precios del IPC de un país. Se representa por:
- Matriz de índices de precios `ipc` que incluye la fila con los índices del númbero base. 
- Vector de ponderaciones `w` de los gastos básicos.
- Fechas correspondientes `fechas` (por meses).
"""
Base.@kwdef struct IndexCPIBase{T, B} <: AbstractCPIBase{T}
    ipc::Matrix{T}
    w::Vector{T}
    fechas::DATETYPE
    baseindex::B

    function IndexCPIBase(ipc::Matrix{T}, w::Vector{T}, fechas::DATETYPE, baseindex::B) where {T, B}
        size(ipc, 2) == length(w) || throw(ArgumentError("número de columnas debe coincidir con vector de ponderaciones"))
        size(ipc, 1) == length(fechas) || throw(ArgumentError("número de filas debe coincidir con vector de fechas"))
        new{T, B}(ipc, w, fechas, baseindex)
    end
end


"""
    VarCPIBase{T, B} <: AbstractCPIBase{T}

Contenedor genérico para de variaciones intermensuales de índices de precios del IPC de un país. Se representa por:
- Matriz de variaciones intermensuales `v`. En las filas contiene los períodos y en las columnas contiene los gastos básicos.
- Vector de ponderaciones `w` de los gastos básicos.
- Fechas correspondientes `fechas` (por meses).
"""
Base.@kwdef struct VarCPIBase{T, B} <: AbstractCPIBase{T}
    v::Matrix{T}
    w::Vector{T}
    fechas::DATETYPE
    baseindex::B

    function VarCPIBase(v::Matrix{T}, w::Vector{T}, fechas::DATETYPE, baseindex::B) where {T, B}
        size(v, 2) == length(w) || throw(ArgumentError("número de columnas debe coincidir con vector de ponderaciones"))
        size(v, 1) == length(fechas) || throw(ArgumentError("número de filas debe coincidir con vector de fechas"))
        new{T, B}(v, w, fechas, baseindex)
    end
end


## Constructores
# Los constructores entre tipos crean copias y asignan nueva memoria

function _getbaseindex(baseindex)
    if length(unique(baseindex)) == 1
        return baseindex[1]
    end
    baseindex
end

"""
    FullCPIBase(df::DataFrame, gb::DataFrame)

Este constructor devuelve una estructura `FullCPIBase` a partir del DataFrame 
de índices de precios `df`, que contiene en las columnas las categorías o gastos 
básicos del IPC y en las filas los períodos por meses. Las ponderaciones se obtienen 
de la estructura `gb`, en la columna denominada `:Ponderacion`.
"""
function FullCPIBase(df::DataFrame, gb::DataFrame)
    # Obtener matriz de índices de precios
    ipc_mat = convert(Matrix, df[!, 2:end])
    # Matrices de variaciones intermensuales de índices de precios
    v_mat = 100 .* (ipc_mat[2:end, :] ./ ipc_mat[1:end-1, :] .- 1)
    # Ponderación de gastos básicos o categorías
    w = gb[!, :Ponderacion]
    # Actualización de fechas
    fechas = df[2, 1]:Month(1):df[end, 1] 
    # Estructura de variaciones intermensuales de base del IPC
    return FullCPIBase(ipc_mat[2:end, :], v_mat, w, fechas, _getbaseindex(ipc_mat[1, :]))
end


"""
    VarCPIBase(df::DataFrame, gb::DataFrame)

Este constructor devuelve una estructura `VarCPIBase` a partir del DataFrame 
de índices de precios `df`, que contiene en las columnas las categorías o gastos 
básicos del IPC y en las filas los períodos por meses. Las ponderaciones se obtienen 
de la estructura `gb`, en la columna denominada `:Ponderacion`.
"""
function VarCPIBase(df::DataFrame, gb::DataFrame)
    # Obtener estructura completa
    cpi_base = FullCPIBase(df, gb)
    # Estructura de variaciones intermensuales de base del IPC
    VarCPIBase(cpi_base)
end

function VarCPIBase(base::FullCPIBase)
    nbase = deepcopy(base)
    VarCPIBase(nbase.v, nbase.w, nbase.fechas, nbase.baseindex)
end

# Obtener VarCPIBase de IndexCPIBase con variaciones intermensuales
VarCPIBase(base::IndexCPIBase) = convert(VarCPIBase, deepcopy(base))

"""
    IndexCPIBase(df::DataFrame, gb::DataFrame)

Este constructor devuelve una estructura `IndexCPIBase` a partir del DataFrame 
de índices de precios `df`, que contiene en las columnas las categorías o gastos 
básicos del IPC y en las filas los períodos por meses. Las ponderaciones se obtienen 
de la estructura `gb`, en la columna denominada `:Ponderacion`.
"""
function IndexCPIBase(df::DataFrame, gb::DataFrame)
    # Obtener estructura completa
    cpi_base = FullCPIBase(df, gb)
    # Estructura de índices de precios de base del IPC
    return IndexCPIBase(cpi_base)
end

function IndexCPIBase(base::FullCPIBase) 
    nbase = deepcopy(base)
    IndexCPIBase(nbase.ipc, nbase.w, nbase.fechas, nbase.baseindex)
end

# Obtener IndexCPIBase de VarCPIBase con capitalización intermensual
IndexCPIBase(base::VarCPIBase) = convert(IndexCPIBase, deepcopy(base))

## Conversión

# Estos métodos sí crean copias a través de la función `convert` de los campos
convert(::Type{T}, base::VarCPIBase) where {T <: AbstractFloat} = 
    VarCPIBase(convert.(T, base.v), convert.(T, base.w), base.fechas, convert.(T, base.baseindex))
convert(::Type{T}, base::IndexCPIBase) where {T <: AbstractFloat} = 
    IndexCPIBase(convert.(T, base.ipc), convert.(T, base.w), base.fechas, convert.(T, base.baseindex))
convert(::Type{T}, base::FullCPIBase) where {T <: AbstractFloat} = 
    FullCPIBase(convert.(T, base.ipc), convert.(T, base.v), convert.(T, base.w), base.fechas, convert.(T, base.baseindex))

# Estos métodos no crean copias, como se indica en la documentación: 
# > If T is a collection type and x a collection, the result of convert(T, x) 
# > may alias all or part of x.
# Al convertir de esta forma se muta la matriz de variaciones intermensuales y se
# devuelve el mismo tipo, pero sin asignar nueva memoria
function convert(::Type{IndexCPIBase}, base::VarCPIBase)
    vmat = base.v
    capitalize!(vmat, base.baseindex)
    IndexCPIBase(vmat, base.w, base.fechas, base.baseindex)
end

function convert(::Type{VarCPIBase}, base::IndexCPIBase)
    ipcmat = base.ipc
    varinterm!(ipcmat, base.baseindex)
    VarCPIBase(ipcmat, base.w, base.fechas, base.baseindex)
end

# Tipo de flotante del contenedor
eltype(::AbstractCPIBase{T}) where {T} = T


## Métodos para mostrar los tipos

function _formatdate(fecha)
    Dates.format(fecha, dateformat"u-yyyy")
end

function summary(io::IO, base::AbstractCPIBase)
    field = hasproperty(base, :v) ? :v : :ipc
    periodos, gastos = size(getproperty(base, field))
    print(io, typeof(base), ": ", periodos, " × ", gastos)
end

function show(io::IO, base::AbstractCPIBase)
    field = hasproperty(base, :v) ? :v : :ipc
    periodos, gastos = size(getproperty(base, field))
    print(io, typeof(base), ": ", periodos, " períodos × ", gastos, " gastos básicos ")
    datestart, dateend = _formatdate.((base.fechas[begin], base.fechas[end]))
    print(io, datestart, "-", dateend)
end



## CountryStructure

"""
    CountryStructure{N, T <: AbstractFloat}

Tipo abstracto que representa el conjunto de bases del IPC de un país.
"""
abstract type CountryStructure{N, T <: AbstractFloat} end

"""
    UniformCountryStructure{N, T, B} <: CountryStructure{N, T}

Estructura que representa el conjunto de bases del IPC de un país, 
posee el campo `base`, que es una tupla de la estructura `VarCPIBase`. Todas
las bases deben tener el mismo tipo de índice base.
"""
struct UniformCountryStructure{N, T, B} <: CountryStructure{N, T}
    base::NTuple{N, VarCPIBase{T, B}} 
end

# Este tipo se puede utilizar con datos cuyos primeros índices no sean todos 100
"""
    MixedCountryStructure{N, T} <: CountryStructure{N, T}

Estructura que representa el conjunto de bases del IPC de un país, 
posee el campo `base`, que es una tupla de la estructura `VarCPIBase`, cada una 
con su propio tipo de índices base B. Este tipo es una colección de un tipo abstracto.
"""
struct MixedCountryStructure{N, T} <: CountryStructure{N, T}
    base::NTuple{N, VarCPIBase{T, B} where B} 
end

# Anotar también como VarCPIBase...
UniformCountryStructure(bases::Vararg{VarCPIBase{T, B}, N}) where {N, T, B} = UniformCountryStructure{N, T, B}(bases)
MixedCountryStructure(bases::Vararg{VarCPIBase}) = MixedCountryStructure(bases)

function summary(io::IO, cst::CountryStructure)
    datestart, dateend = _formatdate.((cst.base[begin].fechas[begin], cst.base[end].fechas[end]))
    print(io, typeof(cst), ": ", datestart, "-", dateend)
end

function show(io::IO, cst::CountryStructure)
    l = length(cst.base)
    println(io, typeof(cst), " con ", l, " bases")
    for base in cst.base
        println(io, "|─> ", sprint(show, base))
    end
end

# Conversión

# Este método crea una copia a través de los métodos de conversión de bases
function convert(::Type{T}, cst::CountryStructure) where {T <: AbstractFloat}
    # Convert each base to type T
    conv_b = convert.(T, cst.base)
    getunionalltype(cst)(conv_b)
end

# Acceso 

"""
    getindex(cst::CountryStructure, i::Int)

Devuelve la base número `i` de un contenedor `CountryStructure`.
"""
getindex(cst::CountryStructure, i::Int) = cst.base[i]

# Función de ayuda para obtener los índices que corresponden a una fecha
# específica de una base
function _base_index(cst, date, retfirst=true)
    for (b, base) in enumerate(cst.base)
        fechas = base.fechas
        dateindex = findfirst(fechas .== date)
        if !isnothing(dateindex)
            return b, dateindex
        end
    end
    # return first or last
    if retfirst
        1, 1
    else
        length(cst.base), size(cst.base[end].v, 1)
    end
end


"""
    getunionalltype(::UniformCountryStructure)

Devuelve el tipo `UniformCountryStructure`. Utilizado al llamar
`getunionalltype` sobre un `CountryStructure` para obtener el tipo concreto
`UnionAll`. 
"""
getunionalltype(::UniformCountryStructure) = UniformCountryStructure


"""
    getunionalltype(::MixedCountryStructure)

Devuelve el tipo `MixedCountryStructure`. Utilizado al llamar `getunionalltype`
sobre un `CountryStructure` para obtener el tipo concreto `UnionAll`.
"""
getunionalltype(::MixedCountryStructure) = MixedCountryStructure


"""
    getindex(cst::CountryStructure, startdate::Date, finaldate::Date)

Devuelve una copia del `CountryStructure` con las bases modificadas para tener
observaciones entre las fechas indicada por `startdate` y `finaldate`.
"""
function getindex(cst::CountryStructure, startdate::Date, finaldate::Date)

    # Obtener base y fila de inicio
    start_base, start_index = _base_index(cst, startdate, true)
    final_base, final_index = _base_index(cst, finaldate, false)

    bases = deepcopy(cst.base[start_base:final_base])
    if start_base == final_base
        # copy same base and slice
        @debug "Fechas en la misma base"
        # @info bases[1]
        onlybase = bases[1]
        newbase = VarCPIBase(
            onlybase.v[start_index:final_index, :], 
            copy(onlybase.w), onlybase.fechas[start_index:final_index], copy(onlybase.baseindex))
        
        return getunionalltype(cst)(newbase)
    else 
        # different bases
        @debug "Fechas en diferentes bases"
        firstbase = bases[begin]
        lastbase = bases[end]
        newstart = VarCPIBase(
            firstbase.v[start_index:end, :], 
            copy(firstbase.w), firstbase.fechas[start_index:end], copy(firstbase.baseindex))
        newfinal = VarCPIBase(
            lastbase.v[begin:final_index, :], 
            copy(lastbase.w), lastbase.fechas[begin:final_index], copy(lastbase.baseindex))
        
        if final_base - start_base > 1
            # more than one base
            @debug "Más de dos bases"
            newbases = (newstart, bases[start_base+1:final_base-1], newfinal)
        else
            # only two bases
            @debug "Dos bases"
            newbases = (newstart, newfinal)
            return getunionalltype(cst)(newbases)
        end
    end

end

"""
    getindex(cst::CountryStructure, finaldate::Date)

Devuelve una copia del `CountryStructure` hasta la fecha indicada por `finaldate`.
"""
function getindex(cst::CountryStructure, finaldate::Date)
    startdate = cst.base[1].fechas[1]
    getindex(cst, startdate, finaldate)
end


## Utilidades

"""
    eltype(::CountryStructure{N, T})

Tipo de dato de punto flotante del contenedor de la estructura de país
`CountryStructure`.
"""
eltype(::CountryStructure{N, T}) where {N,T} = T 


"""
    periods(cst::CountryStructure)

Computa el número de períodos (meses) en las bases de variaciones intermensuales
de la estructura de país. 
"""
periods(cst::CountryStructure) = sum(size(b.v, 1) for b in cst.base)


"""
    infl_periods(cst::CountryStructure)

Computa el número de períodos de inflación de la estructura de país. Corresponde
al número de observaciones intermensuales menos las primeras 11 observaciones de
la primera base del IPC.
"""
infl_periods(cst::CountryStructure) = periods(cst) - 11


"""
    infl_periods(cst::CountryStructure)

Fechas correspondientes a la trayectorias de inflación computadas a partir un
`CountryStructure`.
"""
infl_dates(cst::CountryStructure) = 
    cst.base[begin].fechas[12]:Month(1):cst.base[end].fechas[end]