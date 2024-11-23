import os

fn testsuite_begin() {
	os.chdir(os.dir(@FILE))!
}

fn test_run_tests() {
	res := os.system('${os.quoted_path(@VEXE)} tests/run_tests.vsh')
	assert res == 0
}
