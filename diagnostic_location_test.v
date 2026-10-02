module main

import os

fn test_macro_diagnostics_report_the_offending_source_location() {
	os.chdir(@VMODROOT)!
	tmp_dir := os.join_path(os.temp_dir(), 'c2v_macro_diagnostics_${os.getpid()}')
	os.mkdir_all(tmp_dir)!
	defer {
		os.rmdir_all(tmp_dir) or {}
	}
	exe := os.join_path(tmp_dir, 'c2v' + $if windows { '.exe' } $else { '' })
	build := os.execute('${os.quoted_path(@VEXE)} -o ${os.quoted_path(exe)} .')
	assert build.exit_code == 0, build.output
	header := os.join_path(tmp_dir, 'macros.h')
	os.write_file(header, '#define IDENT(expr) expr\n#define BODY(value) _Generic(value, int: 4, default: 0)\n#define FUNCTION_BODY int pick(int value) { return _Generic(value, int: 4, default: 0); }\n')!
	os.write_file(os.join_path(tmp_dir, 'argument.c'), '#include "macros.h"\nint pick(int value) {\n    return IDENT(_Generic(value, int: 4, default: 0));\n}\n')!
	os.write_file(os.join_path(tmp_dir, 'body.c'), '#include "macros.h"\nint pick(int value) {\n    return BODY(value);\n}\n')!
	os.write_file(os.join_path(tmp_dir, 'nested_body.c'), '#include "macros.h"\nint pick(int value) {\n    return IDENT(BODY(value));\n}\n')!
	os.write_file(os.join_path(tmp_dir, 'local_nested_body.c'), '#define IDENT(expr) expr\n#define BODY(value) _Generic(value, int: 4, default: 0)\nint pick(int value) {\n    return IDENT(BODY(value));\n}\n')!
	os.write_file(os.join_path(tmp_dir, 'byte_zero.cpp'), 'FUNCTION_BODY\nint main(void) { return pick(1); }\n')!
	expected_locations := {
		'argument.c':          ':3:18 (offset 59)'
		'body.c':              ':3:12 (offset 53)'
		'nested_body.c':       ':3:12 (offset 53)'
		'local_nested_body.c': ':4:12 (offset 114)'
		'byte_zero.cpp':       ':1:1 (offset 0)'
	}
	for strict in [false, true] {
		for name, location in expected_locations {
			config := os.join_path(tmp_dir, 'c2v.toml')
			flags := if name == 'byte_zero.cpp' { '-include "${header}"' } else { '' }
			os.write_file(config, "[project]\ngenerate_stubs = ${!strict}\nrequire_no_stubs = ${strict}\nadditional_flags = '${flags}'\n")!
			mut process := os.new_process(exe)
			process.set_args([os.join_path(tmp_dir, name)])
			mut environment := os.environ()
			environment['C2V_CONFIG'] = config
			process.set_environment(environment)
			process.set_redirect_stdio()
			process.run()
			process.wait()
			output := process.stdout_slurp() + process.stderr_slurp()
			code := process.code
			process.close()
			assert code == if strict { 1 } else { 0 }, output
			assert output.contains('GenericSelectionExpr'), output
			assert output.contains('${name}${location}'), output
			assert output.contains(if strict {
				'error: unhandled expression'
			} else {
				'WARNING: Unhandled expr()'
			}), output
		}
	}
}
