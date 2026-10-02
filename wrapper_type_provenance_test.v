module main

import os

fn test_wrapper_directory_keeps_unrelated_private_records_out_of_opaque_apis() {
	os.chdir(@VMODROOT)!
	root := os.join_path(os.temp_dir(), 'c2v_wrapper_type_provenance_${os.getpid()}')
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	exe := os.join_path(root, 'c2v')
	build := os.execute('${os.quoted_path(@VEXE)} -o ${os.quoted_path(exe)} .')
	assert build.exit_code == 0, build.output
	for name in ['private', 'alias', 'reverse', 'connected', 'mixed', 'after'] {
		connected := name in ['connected', 'mixed', 'after']
		input := os.join_path(root, name)
		output := os.join_path(input, 'api')
		os.mkdir_all(input) or { panic(err) }
		os.write_file(os.join_path(input, 'c2v.toml'), '[project]\nwrapper_module_name = "api"\noutput_dirname = "api"\n') or { panic(err) }
		public_header := os.join_path(input, 'a.h').replace('\\', '/')
		os.write_file(public_header, 'struct Context;\n#ifdef __cplusplus\nextern "C" {\n#endif\nstruct Context *get_context(void);\nlong long inspect_context(struct Context *entry);\nunsigned long opaque_size(void);\n#ifdef __cplusplus\n}\n#endif\n') or { panic(err) }
		late_header := os.join_path(input, 'zz.h').replace('\\', '/')
		late_prefix := if connected { '#include "a.h"\n' } else { 'struct Context;\n' }
		os.write_file(late_header, late_prefix + 'long long inspect_again(struct Context *entry);\n') or { panic(err) }
		private_filename := if name == 'reverse' {
			'0_private.c'
		} else if name == 'mixed' {
			'z.cpp'
		} else {
			'z.c'
		}
		private_source := os.join_path(input, private_filename)
		private_type := if name == 'alias' { 'PrivateContext' } else { 'Context' }
		definition := if name == 'alias' {
			'typedef struct Context { int value; } PrivateContext;\n'
		} else if name == 'mixed' {
			// The same physical C header becomes RecordDecl in its C AST and
			// CXXRecordDecl when included by this accepted C++ definition.
			os.write_file(os.join_path(input, 'z.hpp'), '#include "a.h"\nstruct Context { long long value; };\n') or { panic(err) }
			'#include "z.hpp"\n'
		} else if name == 'after' {
			// Clang puts previousDecl on the included forward declaration,
			// pointing back to this earlier complete definition.
			'struct Context { long long value; };\n#include "a.h"\n'
		} else if connected {
			'#include "a.h"\nstruct Context { long long value; };\n'
		} else {
			'struct Context { int value; };\n'
		}
		c_type := if name == 'alias' { private_type } else { 'struct Context' }
		linkage := if name == 'mixed' { 'extern "C" ' } else { '' }
		os.write_file(private_source, definition + '${linkage}unsigned long private_size(void) { return sizeof(${c_type}); }\n${linkage}long long inspect_private(${c_type} *entry) { return entry->value; }\n') or { panic(err) }
		// Compile distinct translation units: the opaque library uses an eight
		// byte field, while an unrelated private record uses a four byte field.
		opaque_source := os.join_path(root, '${name}_opaque.c')
		opaque_object := os.join_path(root, '${name}_opaque.o')
		private_object := os.join_path(root, '${name}_private.o')
		os.write_file(opaque_source, '#include "${public_header}"\nstruct Context { long long value; };\nstatic struct Context storage = {4294967297LL};\nstruct Context *get_context(void) { return &storage; }\nlong long inspect_context(struct Context *entry) { return entry->value; }\nlong long inspect_again(struct Context *entry) { return entry->value; }\nunsigned long opaque_size(void) { return sizeof(struct Context); }\n') or { panic(err) }
		for source, object in {
			opaque_source:  opaque_object
			private_source: private_object
		} {
			compiler := if os.file_ext(source) == '.cpp' { 'c++' } else { 'cc' }
			native := os.execute('${compiler} -c ${os.quoted_path(source)} -o ${os.quoted_path(object)}')
			assert native.exit_code == 0, native.output
		}
		translate := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(input)}')
		assert translate.exit_code == 0, translate.output
		mut generated := ''
		for path in os.walk_ext(output, '.v') {
			generated += os.read_file(path) or { panic(err) }
		}
		api_type := if connected { 'Context' } else { 'C.Context' }
		assert generated.contains('pub fn get_context() &${api_type}'), generated
		assert generated.contains('pub fn inspect_context(entry &${api_type})'), generated
		assert generated.contains('pub fn inspect_again(entry &${api_type})'), generated
		assert generated.contains('struct ${private_type} {'), generated
		assert generated.count('struct C.Context {') == if connected { 0 } else { 1 }, generated
		field_type := if connected { 'i64' } else { 'i32' }
		assert generated.split('\n').any(it.fields() == ['value', field_type]), generated
		bridge := os.join_path(root, '${name}_bridge.h').replace('\\', '/')
		os.write_file(bridge, '#include "${public_header}"\n#include "${late_header}"\nunsigned long private_size(void);\nlong long inspect_private(void *entry);\n') or { panic(err) }
		connected_call := if connected {
			'assert inspect_context(&private_entry) == 7\n'
		} else {
			''
		}
		private_size := if connected { 8 } else { 4 }
		os.write_file(os.join_path(output, 'native_check.v'), 'module api\npub fn verify_native() {\nentry := get_context()\nassert inspect_context(entry) == 4294967297\nassert inspect_again(entry) == 4294967297\nassert opaque_size() == 8\nassert private_size() == ${private_size}\nmut private_entry := ${private_type}{value: 7}\nassert inspect_private(&private_entry) == 7\n${connected_call}}\n') or { panic(err) }
		consumer := os.join_path(input, 'consumer.v')
		os.write_file(consumer, 'module main\nimport api\n#flag ${os.quoted_path(opaque_object)}\n#flag ${os.quoted_path(private_object)}\n#include "${bridge}"\nfn main() { api.verify_native()\nprintln("separate contexts native passed") }\n') or { panic(err) }
		runtime := os.execute('${os.quoted_path(@VEXE)} run ${os.quoted_path(consumer)}')
		assert runtime.exit_code == 0, runtime.output
		assert runtime.output.trim_space() == 'separate contexts native passed', runtime.output
		if name == 'private' {
			// The generated type boundary also rejects passing the private
			// four byte record to the native opaque eight byte API.
			os.write_file(os.join_path(output, 'negative_context.v'), 'module api\nfn reject_private_context() {\nmut entry := Context{value: 7}\n_ = inspect_context(&entry)\n}\n') or { panic(err) }
			negative := os.execute('${os.quoted_path(@VEXE)} -check ${os.quoted_path(consumer)}')
			assert negative.exit_code != 0, negative.output
			assert negative.output.contains('cannot use') && negative.output.contains('C.Context'), negative.output
		}
	}
}
