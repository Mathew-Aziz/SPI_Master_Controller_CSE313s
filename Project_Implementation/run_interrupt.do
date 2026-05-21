quit -sim
make compile
vsim -coverage work.tb_top +TESTNAME=interrupt_test +UVM_TESTNAME=interrupt_test +SEED=1
do wave.do
run -all