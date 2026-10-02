module main

import os

fn test_c_wrapper_directory_preserves_direct_system_include_order() {
	if os.user_os() != 'macos' {
		return
	}
	os.chdir(@VMODROOT)!
	root := os.join_path(os.temp_dir(), 'c2v_wrapper_include_order_${os.getpid()}')
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	exe := os.join_path(root, 'c2v')
	build := os.execute('${os.quoted_path(@VEXE)} -o ${os.quoted_path(exe)} .')
	assert build.exit_code == 0, build.output
	for name in ['c', 'mixed'] {
		check_wrapper_directory_include_order(exe, os.join_path(root, name), name == 'mixed')
	}
}

fn check_wrapper_directory_include_order(exe string, input string, mixed_cpp bool) {
	root := os.dir(input)
	output := os.join_path(input, 'reviewapi')
	os.mkdir_all(input) or { panic(err) }
	// The prerequisite is selected by a file-specific flag, and declarations
	// from the later header must preserve its original direct include order.
	header := os.join_path(input, 'api.h').replace('\\', '/')
	os.write_file(header, '#ifndef REVIEW_INCLUDE_CHAIN\n#error Requires the file-specific flag\n#endif\n#include <xlocale.h>\n#include <langinfo.h>\nchar *nl_langinfo_l(nl_item item, locale_t locale);\nlocale_t newlocale(int mask, const char *name, locale_t base);\nint freelocale(locale_t locale);\n') or {
		panic(err)
	}
	os.write_file(os.join_path(input, 'c2v.toml'), '[project]\nwrapper_module_name = "reviewapi"\noutput_dirname = "reviewapi"\n[\'api.h\']\nadditional_flags = "-DREVIEW_INCLUDE_CHAIN"\n') or {
		panic(err)
	}
	// A rejected recovered AST must not contribute its direct system includes.
	os.write_file(os.join_path(input, 'z_invalid.h'), '#include <wctype.h>\nUnknown invalid;\n') or {
		panic(err)
	}
	if mixed_cpp {
		os.write_file(os.join_path(input, 'zz_cpp.hpp'), 'struct UnrelatedCpp { int value; };\n') or {
			panic(err)
		}
	}
	translate := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(input)}')
	assert translate.exit_code == 0, translate.output
	assert translate.output.contains('skipping wrapper header ./z_invalid.h'), translate.output
	assert !translate.output.contains('skipping wrapper header ./api.h'), translate.output
	if mixed_cpp {
		assert !translate.output.contains('skipping wrapper header ./zz_cpp.hpp'), translate.output
		assert os.walk_ext(output, '.v').any((os.read_file(it) or { '' }).contains('UnrelatedCpp')), translate.output
	}
	shared := os.read_file(os.join_path(output, '0_external.c.v')) or { panic(err) }
	prerequisite := shared.index('#include <xlocale.h>') or { panic(shared) }
	dependent := shared.index('#include <langinfo.h>') or { panic(shared) }
	assert prerequisite < dependent, shared
	assert !shared.contains('#include <wctype.h>'), shared
	// A normal importing application calls libc through the generated wrappers.
	// Copy the locale-owned string before freeing the native locale.
	os.write_file(os.join_path(output, 'native_check.v'), "module reviewapi\n#define c2v_review_locale_mask() LC_ALL_MASK\n#define c2v_review_codeset() CODESET\nfn C.c2v_review_locale_mask() i32\nfn C.c2v_review_codeset() i32\npub fn native_codeset() string {\nlocale := newlocale(C.c2v_review_locale_mask(), c'C', unsafe { nil })\nassert locale != unsafe { nil }\nvalue := nl_langinfo_l(C.c2v_review_codeset(), locale)\nassert value != unsafe { nil }\ntext := unsafe { (&u8(value)).vstring().clone() }\nfreelocale(locale)\nreturn text\n}\n") or {
		panic(err)
	}
	consumer := os.join_path(input, 'consumer.v')
	os.write_file(consumer, 'module main\nimport reviewapi\nfn main() { println(reviewapi.native_codeset()) }\n') or {
		panic(err)
	}
	native_source := os.join_path(root, 'native.c')
	native_exe := os.join_path(root, 'native')
	os.write_file(native_source, '#include <stdio.h>\n#include "${header}"\nint main(void) { locale_t locale = newlocale(LC_ALL_MASK, "C", 0); if (!locale) return 1; puts(nl_langinfo_l(CODESET, locale)); freelocale(locale); return 0; }\n') or {
		panic(err)
	}
	native_build := os.execute('cc -DREVIEW_INCLUDE_CHAIN ${os.quoted_path(native_source)} -o ${os.quoted_path(native_exe)}')
	assert native_build.exit_code == 0, native_build.output
	native := os.execute(os.quoted_path(native_exe))
	assert native.exit_code == 0, native.output
	translated := os.execute('${os.quoted_path(@VEXE)} run ${os.quoted_path(consumer)}')
	assert translated.exit_code == 0, translated.output
	assert translated.output == native.output, translated.output
	assert native.output.trim_space().len > 0
}
