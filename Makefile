PY = python3
IV = iverilog

.PHONY: test sim clean

test:
	$(PY) tests/run_tests.py

# Requires Icarus Verilog ( rtl simulation; hex files come from `make test` )
sim:
	cd build/$(T) && $(IV) -o sim ../../rtl/*.v ../../tb/tb_core.v && ./sim

clean:
	rm -rf build
