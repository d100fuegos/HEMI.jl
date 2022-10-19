using DrWatson
@quickactivate "HEMI" 

using HEMI 

## Parallel processing
using Distributed
nprocs() < 5 && addprocs(4, exeflags="--project")
@everywhere using HEMI 

## Otras librerías
using DataFrames, Chain


loadpath = datadir("results", "no_trans","tray_infl","mse")
tray_dir = joinpath(loadpath, "tray_infl")

combination_savepath  = datadir("results","no_trans","optim_combination","mse")

data_loadpath = datadir("results", "no_trans", "data", "NOT_data.jld2")
NOT_GTDATA = load(data_loadpath, "NOT_GTDATA")

gtdata_eval = NOT_GTDATA[Date(2021, 12)]

df_results = collect_results(loadpath)

@chain df_results begin 
    select(:measure, :mse)
end

# DataFrame de combinación 
combine_df = @chain df_results begin 
    select(:measure, :mse, :inflfn, 
        :path => ByRow(p -> joinpath(tray_dir, basename(p))) => :tray_path
    )
    sort(:mse)
end

tray_infl = mapreduce(hcat, combine_df.tray_path) do path
    load(path, "tray_infl")
end

resamplefn = df_results[1, :resamplefn]
trendfn = df_results[1, :trendfn]
paramfn = InflationTotalRebaseCPI(36, 3) #df_results[1, :paramfn]
param = InflationParameter(paramfn, resamplefn, trendfn)
tray_infl_pob = param(gtdata_eval)

functions = combine_df.inflfn
components_mask = [!(fn isa InflationFixedExclusionCPI) for fn in functions]

combine_period = EvalPeriod(Date(2011, 12), Date(2021, 12), "combperiod") 
periods_filter = eval_periods(gtdata_eval, combine_period)

a_optim = share_combination_weights(
    tray_infl[periods_filter, components_mask, :],
    tray_infl_pob[periods_filter],
    show_status=true
)

#Insertamos el 0 en el vector de pesos en el lugar correspondiente a exclusion fija
insert!(a_optim, findall(.!components_mask)[1],0)

optmse2023 = CombinationFunction(
    functions...,
    a_optim, 
    "Subyacente óptima MSE 2023 no transable"
)

wsave(joinpath(combination_savepath,"optmse2023.jld2"), "optmse2023", optmse2023)

# using PrettyTables
# pretty_table(components(optmse2023))
# ┌───────────────────────────────────────────────┬────────────┐
# │                                       measure │    weights │
# │                                        String │    Float32 │
# ├───────────────────────────────────────────────┼────────────┤
# │   Media Truncada Equiponderada (24.71, 96.28) │   0.999999 │
# │        Media Truncada Ponderada (11.2, 99.55) │ 5.25671e-7 │
# │  Inflación de exclusión dinámica (0.81, 3.78) │ 3.78395e-8 │
# │                     Percentil ponderado 69.34 │ 1.82954e-8 │
# │ Exclusión fija de gastos básicos IPC (13, 18) │        0.0 │
# │                 Percentil equiponderado 71.84 │ 2.03072e-9 │
# └───────────────────────────────────────────────┴────────────┘

######################################################################################
################## INTERVALO DE CONFIANZA ############################################
######################################################################################

a = reshape(a_optim,(1,length(a_optim),1))
b = reshape(tray_infl_pob,(length(tray_infl_pob),1,1))
w_tray = sum(a.*tray_infl,dims=2)
error_tray = dropdims(w_tray .- b,dims=2)

period_b00 = EvalPeriod(Date(2001,12), Date(2010,12), "b00")
period_trn = EvalPeriod(Date(2011,01), Date(2011,11), "trn")
period_b10 = EvalPeriod(Date(2011,12), Date(2021,12), "b10")

b00_mask = eval_periods(gtdata_eval, period_b00)
trn_mask = eval_periods(gtdata_eval, period_trn)
b10_mask = eval_periods(gtdata_eval, period_b10)

tray_b00 = error_tray[b00_mask, :]
tray_trn = error_tray[trn_mask, :]
tray_b10 = error_tray[b10_mask, :]

quant_0125 = quantile.(vec.([tray_b00,tray_trn,tray_b10]),0.0125)  
quant_9875 = quantile.(vec.([tray_b00,tray_trn,tray_b10]),0.9875) 

bounds =transpose(hcat(-quant_0125,-quant_9875))

# pretty_table(hcat(["upper","lower"],bounds),["","b00","T","b10"])
# ┌───────┬──────────┬───────────┬───────────┐
# │       │      b00 │         T │       b10 │
# ├───────┼──────────┼───────────┼───────────┤
# │ upper │  1.51019 │   1.57325 │  0.674867 │
# │ lower │ -1.79117 │ -0.413358 │ -0.108492 │
# └───────┴──────────┴───────────┴───────────┘
