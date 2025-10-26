# run_req020_fuzzifiers.do — compile & run fuzzifier TBs (T and dT)
vlib work
vlog -sv +acc trapezoid.sv fuzzifier_T.sv fuzzifier_dT.sv \
           tb_fuzzifier_t_req020.sv tb_fuzzifier_dt_req020.sv
# Reproducible seed if desired:
# vsim -c -sv_seed 12345 work.tb_fuzzifier_t_req020  -do "run -all; quit -f"
# vsim -c -sv_seed 12345 work.tb_fuzzifier_dt_req020 -do "run -all; quit -f"
vsim -c work.tb_fuzzifier_t_req020  -do "run -all; quit -f"
vsim -c work.tb_fuzzifier_dt_req020 -do "run -all; quit -f"
