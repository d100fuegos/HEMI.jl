using DrWatson
@quickactivate "HEMI" 

using HEMI 

## Parallel processing
using Distributed
nprocs() < 5 && addprocs(4, exeflags="--project")
@everywhere using HEMI 

## Otras librerías
using DataFrames, Chain

data_loadpath = datadir("results", "no_trans", "data", "NOT_data.jld2")
NOT_GTDATA = load(data_loadpath, "NOT_GTDATA")

############ DATOS A UTILIZAR #########################

gtdata_eval = GTDATA[Date(2021, 12)]

########### CARGAMOS TRAYECTORIAS ###############

# DEFINIMOS LOS PATHS 
loadpath = datadir("results","no_trans", "tray_infl", "corr")
tray_dir = joinpath(loadpath, "tray_infl")
loadpath_2019 = datadir("results","no_trans", "tray_infl_2019", "corr")
tray_dir_2019 = joinpath(loadpath_2019, "tray_infl")
combination_loadpath  = datadir("results","no_trans","optim_combination","corr")

save_results = datadir("results","no_trans","eval","corr")

# RECOLECTAMOS LOS DATAFRAMES
df      = collect_results(loadpath)
df_19   = collect_results(loadpath_2019)
optim   = collect_results(combination_loadpath)

# CARGAMOS LAS TRAYECTORIAS CORRESPONDIENTES
df[!,:tray_path] = joinpath.(tray_dir,basename.(df.path))
df[!,:tray_infl] = [x["tray_infl"] for x in load.(df.tray_path)]
df[!, :inflfn_type] = typeof.(df.inflfn)

df_19[!,:tray_path] = joinpath.(tray_dir_2019,basename.(df_19.path))
df_19[!,:tray_infl] = [x["tray_infl"] for x in load.(df_19.tray_path)]
df_19[!, :inflfn_type] = typeof.(df.inflfn)

######## CARGAMOS LOS PESOS #####################################

df_weights = collect_results(combination_loadpath)
optcorr = df_weights[1,:optcorr2023]


######## HACEMOS COINCIDIR LAS TRAYECTORIAS CON SUS PESOS Y RENORMALIZAMOS LA MAI ####################

opt_w = DataFrame(
    :inflfn => [x for x in optcorr.ensemble.functions],
    :inflfn_type => [typeof(x) for x in optcorr.ensemble.functions], 
    :weight => optcorr.weights
) 

# DATAFRAMES RENORMALIZXADOS CON TRAYECTORIAS PONDERADAS
df_renorm = innerjoin(df,opt_w[:,[:inflfn_type,:weight]], on = :inflfn_type)[:,[:inflfn,:inflfn_type,:weight, :tray_infl]]
df_renorm[!,:w_tray] = df_renorm.weight .* df_renorm.tray_infl

df_renorm_19 = innerjoin(df_19,opt_w[:,[:inflfn_type,:weight]], on = :inflfn_type)[:,[:inflfn,:inflfn_type,:weight, :tray_infl]]
df_renorm_19[!,:w_tray] = df_renorm_19.weight .* df_renorm_19.tray_infl

################# OBTENEMOS LAS TRAYECTORIAS #################################################

w_tray     = sum(df_renorm.w_tray, dims=1)[1]
w_tray_19  = sum(df_renorm_19.w_tray, dims=1)[1]

##### AGREGAMOS COMBINACIONES OPTIMAS AL DATAFRAME RENORMALIZADO #############################

df_renorm    = vcat(df_renorm, DataFrame(:inflfn => [optcorr], :tray_infl => [w_tray]), cols=:union)
df_renorm_19 = vcat(df_renorm_19, DataFrame(:inflfn => [optcorr], :tray_infl => [w_tray_19]), cols=:union)


############# DEFINIMOS PARAMETROS ######################################################

# PARAMETRO HASTA 2021
param = InflationParameter(
    InflationTotalRebaseCPI(36, 3), 
    ResampleScrambleVarMonths(), 
    TrendRandomWalk()
)

# PARAMETRO HASTA 2019 (para evaluacion en periodo de optimizacion de medidas individuales)
param_2019 = InflationParameter(
    InflationTotalRebaseCPI(36, 2), 
    ResampleScrambleVarMonths(), 
    TrendRandomWalk()
)

# TRAYECOTRIAS DE LOS PARAMETROS 
tray_infl_pob      = param(gtdata_eval)
tray_infl_pob_19   = param_2019(gtdata_eval[Date(2019,12)])


############ DEFINIMOS PERIODOS DE EVALUACION ############################################

period_b00 = EvalPeriod(Date(2001,12), Date(2010,12), "b00")
period_trn = EvalPeriod(Date(2011,01), Date(2011,11), "trn")
period_b10 = EvalPeriod(Date(2011,12), Date(2021,12), "b10")

b00_mask = eval_periods(gtdata_eval, period_b00)
trn_mask = eval_periods(gtdata_eval, period_trn)
b10_mask = eval_periods(gtdata_eval, period_b10)


##### EVALUAMOS ############################

# PERIDO COMPLETO (2001-2021)
df_renorm[!,:complete_corr] = (x -> eval_metrics(x,tray_infl_pob)[:corr]).(df_renorm.tray_infl)

# PERIDO BASE 2000
df_renorm[!,:b00_corr] = (x -> eval_metrics(x[b00_mask,:,:],tray_infl_pob[b00_mask])[:corr]).(df_renorm.tray_infl)

# PERIDO DE TRANSICION
df_renorm[!,:trn_corr] = (x -> eval_metrics(x[trn_mask,:,:],tray_infl_pob[trn_mask])[:corr]).(df_renorm.tray_infl)

# PERIDO BASE 2010
df_renorm[!,:b10_corr] = (x -> eval_metrics(x[b10_mask,:,:],tray_infl_pob[b10_mask])[:corr]).(df_renorm.tray_infl)

# PERIODO 2001-2019
df_renorm[!,:b19_corr] = (x -> eval_metrics(x,tray_infl_pob_19)[:corr]).(df_renorm_19.tray_infl)




######## PULIMOS LOS RESULTADOS ##########################

# Le agregamos nombres a las funciones
df_renorm[!,:measure_name] = measure_name.(df_renorm.inflfn)

# Le devolvemos su peso a la OPTIMA y a la MAI OPTIMA
df_renorm[(x -> isa(x,CombinationFunction)).(df_renorm.inflfn),:weight] = [1]

# Defininimos una funcion para ordenar los resultados en el orden de filas deseado.
function inflfn_rank(x)
    if x isa InflationPercentileEq
        out = 1
    elseif x isa InflationPercentileWeighted
        out = 2
    elseif x isa InflationTrimmedMeanEq
        out = 3
    elseif x isa InflationTrimmedMeanWeighted
        out = 4
    elseif x isa InflationDynamicExclusion
        out = 5
    elseif x isa InflationFixedExclusionCPI
        out = 6
    elseif x isa CombinationFunction
        out = 7
        end
    out
end

df_renorm[!,:rank_order] = inflfn_rank.(df_renorm.inflfn)

#ordenamos
sort!(df_renorm,:rank_order)

# Cremos un dataframe final
df_final = df_renorm[:, [:measure_name,:weight,:b00_corr,:trn_corr,:b10_corr,:b19_corr,:complete_corr]]

# using PrettyTables
# pretty_table(df_final)
# ┌───────────────────────────────────────────────┬────────────┬──────────┬──────────┬──────────┬──────────┬───────────────┐
# │                                  measure_name │     weight │ b00_corr │ trn_corr │ b10_corr │ b19_corr │ complete_corr │
# │                                        String │   Float32? │  Float32 │  Float32 │  Float32 │  Float32 │       Float32 │
# ├───────────────────────────────────────────────┼────────────┼──────────┼──────────┼──────────┼──────────┼───────────────┤
# │                 Percentil equiponderado 79.84 │   0.254759 │ 0.856123 │ 0.965268 │ 0.718633 │ 0.945231 │      0.961104 │
# │                      Percentil ponderado 82.2 │  0.0366308 │ 0.838034 │ 0.961798 │ 0.574704 │ 0.948123 │      0.959311 │
# │   Media Truncada Equiponderada (16.41, 98.45) │   0.416954 │ 0.876141 │ 0.966282 │  0.73922 │ 0.950334 │      0.964977 │
# │        Media Truncada Ponderada (31.7, 96.11) │ 3.94964e-6 │ 0.862184 │ 0.965758 │ 0.625316 │ 0.949857 │      0.962533 │
# │  Inflación de exclusión dinámica (0.85, 2.32) │   0.291732 │ 0.865349 │ 0.963341 │  0.64317 │ 0.950124 │      0.963247 │
# │ Exclusión fija de gastos básicos IPC (13, 57) │        0.0 │ 0.880626 │ 0.969444 │ 0.438889 │ 0.949422 │      0.962069 │
# │                   Subyacente óptima CORR 2023 │        1.0 │ 0.893801 │ 0.970262 │ 0.764919 │ 0.953708 │      0.967985 │
# └───────────────────────────────────────────────┴────────────┴──────────┴──────────┴──────────┴──────────┴───────────────┘

# guardamos el resultado
using  CSV
mkpath(save_results)
CSV.write(joinpath(save_results,"eval.csv"), df_final)