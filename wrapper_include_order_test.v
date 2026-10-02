module main

import os

fn test_wrapper_directory_preserves_direct_system_include_order() {
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
	for name in ['c', 'mixed', 'cpp', 'cpp_retry'] {
		check_wrapper_directory_include_order(exe, os.join_path(root, name), name)
	}
}

fn check_wrapper_directory_include_order(exe string, input string, mode string) {
	mixed_cpp := mode == 'mixed'
	header_cpp := mode in ['cpp', 'cpp_retry']
	root := os.dir(input)
	output := os.join_path(input, 'reviewapi')
	os.mkdir_all(input) or { panic(err) }
	// The prerequisite is selected by a file-specific flag, and declarations
	// from the later header must preserve its original direct include order.
	header := os.join_path(input, 'api.h').replace('\\', '/')
	// A C-compatible .h can be explicitly C++; another .h requires the accepted
	// C++ retry. Both retain the declaration-free prerequisite system header.
	cpp_retry := if mode == 'cpp_retry' { '\nnamespace ReviewCppRetry {}\n' } else { '' }
	flags := if mode == 'cpp' { '-DREVIEW_INCLUDE_CHAIN -x c++' } else { '-DREVIEW_INCLUDE_CHAIN' }
	locale_declarations := if header_cpp {
		''
	} else {
		'locale_t newlocale(int mask, const char *name, locale_t base);\nint freelocale(locale_t locale);\n'
	}
	os.write_file(header, '#ifndef REVIEW_INCLUDE_CHAIN\n#error Requires the file-specific flag\n#endif\n#include <xlocale.h>\n#include <langinfo.h>\nchar *nl_langinfo_l(nl_item item, locale_t locale);\n' + locale_declarations + cpp_retry) or {
		panic(err)
	}
	os.write_file(os.join_path(input, 'c2v.toml'), '[project]\nwrapper_module_name = "reviewapi"\noutput_dirname = "reviewapi"\n[\'api.h\']\nadditional_flags = "${flags}"\n') or {
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
	// CPP-only inputs expose just nl_langinfo_l: xlocale.h has no selected
	// declaration, so only the accepted include trace can retain it.
	locale_helpers := if header_cpp {
		'fn C.newlocale(mask i32, name &u8, base voidptr) voidptr\nfn C.freelocale(locale voidptr) i32\n'
	} else {
		''
	}
	create_locale := if header_cpp { 'C.newlocale' } else { 'newlocale' }
	free_locale := if header_cpp { 'C.freelocale' } else { 'freelocale' }
	os.write_file(os.join_path(output, 'native_check.v'), "module reviewapi\n#define c2v_review_locale_mask() LC_ALL_MASK\n#define c2v_review_codeset() CODESET\nfn C.c2v_review_locale_mask() i32\nfn C.c2v_review_codeset() i32\n${locale_helpers}pub fn native_codeset() string {\nlocale := ${create_locale}(C.c2v_review_locale_mask(), c'C', unsafe { nil })\nassert locale != unsafe { nil }\nvalue := nl_langinfo_l(C.c2v_review_codeset(), locale)\nassert value != unsafe { nil }\ntext := unsafe { (&u8(value)).vstring().clone() }\n${free_locale}(locale)\nreturn text\n}\n") or {
		panic(err)
	}
	consumer := os.join_path(input, 'consumer.v')
	os.write_file(consumer, 'module main\nimport reviewapi\nfn main() { println(reviewapi.native_codeset()) }\n') or {
		panic(err)
	}
	native_extension := if header_cpp { 'cpp' } else { 'c' }
	native_source := os.join_path(root, 'native.${native_extension}')
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
