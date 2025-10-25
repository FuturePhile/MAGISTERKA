# run_req020.do — lightweight Questa script for tb_trapezoid_req020
vlib work
vlog -sv +acc trapezoid.sv tb_trapezoid_req020.sv
# Set a fixed seed for reproducibility across OSes if desired
# vsim -c -sv_seed 12345 -coverage work.tb_trapezoid_req020 -do "run -all; quit -f"
vsim -c -coverage work.tb_trapezoid_req020 -do "run -all; quit -f"
