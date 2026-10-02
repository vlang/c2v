module main

import os

fn test_missing_clang_reports_how_to_install_dependency() {
	os.chdir(@VMODROOT)!
	exe := os.join_path(os.temp_dir(), 'c2v_issue_188_${os.getpid()}' + $if windows { '.exe' } $else { '' })
	defer {
		os.rm(exe) or {}
	}
	build := os.execute('${os.quoted_path(@VEXE)} -o ${os.quoted_path(exe)} .')
	assert build.exit_code == 0, build.output
	mut process := os.new_process(exe)
	mut environment := os.environ()
	environment['PATH'] = os.join_path(os.temp_dir(), 'c2v_missing_clang_${os.getpid()}')
	process.set_environment(environment)
	process.set_redirect_stdio()
	process.run()
	process.wait()
	output := process.stdout_slurp() + process.stderr_slurp()
	assert process.code == 1
	assert output.contains('cannot find clang in PATH')
	assert output.contains('Install Clang and add its bin directory to PATH')
	assert !output.contains('V panic')
	assert !output.contains('Backtrace')
	process.close()
}
