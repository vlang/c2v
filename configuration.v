module main

import os
import toml

fn (mut c2v C2V) handle_configuration(args []string) {
	last_path := args.last()
	if os.is_dir(last_path) {
		c2v.is_dir = true
		c2v.target_root = os.real_path(last_path)
		c2v.project_folder = c2v.target_root
		c2v.source_scan_root = c2v.target_root
	} else {
		c2v.is_dir = false
		c2v.target_root = os.dir(os.real_path(last_path))
		c2v.project_folder = c2v.target_root
		c2v.source_scan_root = c2v.target_root
	}
	// Configuration file priority:
	// 1) C2V_CONFIG, but only if it exits
	// 2) project_folder/c2v.toml, but only if it exists
	// 3) Walk up parent directories looking for c2v.toml
	mut c2v_config_file := os.getenv('C2V_CONFIG')
	if c2v_config_file == '' || !os.exists(c2v_config_file) {
		c2v_config_file = ''
		folder_file := os.join_path(c2v.project_folder, 'c2v.toml')
		if os.exists(folder_file) {
			c2v_config_file = folder_file
		} else {
			// Some projects keep c2v.toml in a nested source root (e.g. project/src/c2v.toml).
			for nested in ['src', 'source'] {
				nested_candidate := os.join_path(c2v.project_folder, nested, 'c2v.toml')
				if os.exists(nested_candidate) {
					c2v_config_file = nested_candidate
					c2v.project_folder = os.dir(os.real_path(c2v_config_file))
					c2v.source_scan_root = c2v.project_folder
					break
				}
			}
		}
		if c2v_config_file == '' {
			// Walk up parent directories looking for c2v.toml
			mut dir := c2v.project_folder
			for dir != '/' && dir != '' && dir != '.' {
				parent := os.dir(dir)
				if parent == dir {
					break
				}
				candidate := os.join_path(parent, 'c2v.toml')
				if os.exists(candidate) {
					c2v_config_file = candidate
					c2v.project_folder = parent
					break
				}
				dir = parent
			}
		}
	} else {
		// When C2V_CONFIG is explicitly set, derive project_folder from it
		c2v.project_folder = os.dir(os.real_path(c2v_config_file))
		c2v.source_scan_root = c2v.project_folder
	}
	c2v.read_toml_configuration(c2v_config_file)
	c2v.set_config_overrides_for_project()
}

fn (mut c2v C2V) get_additional_flags(_ string) string {
	return '${c2v.project_additional_flags} ${c2v.file_additional_flags} '
}

fn (mut c2v C2V) get_globals_path() string {
	return c2v.project_globals_path
}

fn (mut c2v C2V) read_toml_configuration(toml_file string) {
	if toml_file == '' {
		return
	}
	vprintln('> reading from toml configuration file: ${toml_file}')
	c2v.conf = toml.parse_file(toml_file) or { panic(err) }
	// dump(c2v.conf)
}

// called once per invocation
fn (mut c2v C2V) set_config_overrides_for_project() {
	c2v.project_uses_sdl = c2v.conf.value('project.uses_sdl').default_to(false).bool()
	c2v.project_output_dirname =
		c2v.conf.value('project.output_dirname').default_to('c2v_output').string()
	c2v.project_additional_flags =
		c2v.conf.value('project.additional_flags').default_to('-I.').string()
	c2v.wrapper_module_name = c2v.conf.value('project.wrapper_module_name').default_to('').string()
	c2v.skeleton_mode = c2v.conf.value('project.skeleton_mode').default_to(false).bool()
	c2v.project_single_module = c2v.conf.value('project.single_module').default_to(false).bool()
	c2v.project_generate_stubs = c2v.conf.value('project.generate_stubs').default_to(true).bool()
	c2v.project_require_no_stubs =
		c2v.conf.value('project.require_no_stubs').default_to(false).bool()
	c2v.project_require_main = c2v.conf.value('project.require_main').default_to(false).bool()
	c2v.project_source_manifest = c2v.conf.value('project.source_manifest').default_to('').string()
	c2v.project_native_manifest =
		c2v.conf.value('project.native_source_manifest').default_to('').string()
	if c2v.project_require_no_stubs {
		if c2v.skeleton_mode {
			c2v.verror('project.require_no_stubs cannot be combined with project.skeleton_mode')
		}
		if c2v.project_generate_stubs {
			c2v.verror('project.require_no_stubs requires project.generate_stubs = false')
		}
		if c2v.is_dir && !c2v.project_single_module {
			c2v.verror('project.require_no_stubs directory translation requires project.single_module = true')
		}
	}
	c2v.keep_ast = c2v.conf.value('keep_ast').default_to(false).bool()
	c2v.project_module_name = c2v.conf.value('project.module_name').default_to('main').string()
	c2v.skip_comments = os.args.contains('-skip_comments')
		|| c2v.conf.value('project.skip_comments').default_to(false).bool()
	// One translated C file => one V file per original source file (split.v).
	c2v.split_files = !c2v.is_dir && !c2v.is_wrapper
		&& (os.args.contains('-split_files') || c2v.conf.value('project.split_files').default_to(false).bool())
	// External C libraries: their headers are parsed with the project, and the
	// V build links them. `uses_sdl = true` is shorthand for pkg_config = ["sdl2"].
	c2v.project_pkg_config = c2v.conf.value('project.pkg_config').default_to([]toml.Any{}).array().map(it.string())
	c2v.project_link_flags = c2v.conf.value('project.link_flags').default_to('').string()
	if c2v.project_uses_sdl {
		sdl_cflags := get_sdl_cflags()
		c2v.project_additional_flags += ' ' + sdl_cflags
		if 'sdl2' !in c2v.project_pkg_config {
			c2v.project_pkg_config << 'sdl2'
		}
	}
	for pkg in c2v.project_pkg_config {
		if pkg == 'sdl2' && c2v.project_uses_sdl {
			continue
		}
		c2v.project_additional_flags += ' ' + get_pkg_config_cflags(pkg)
	}
	c2v.project_output_root = os.join_path(c2v.target_root, c2v.project_output_dirname)
	c2v.project_globals_path = os.join_path(c2v.project_output_root, '0_globals.v')
}

// called once per each .c file
fn (mut c2v C2V) set_config_overrides_for_file(path string) {
	fname := os.file_name(path)
	c2v.file_additional_flags =
		c2v.conf.value("'${fname}'.additional_flags").default_to('').string()
	// Also check for directory-level flags by matching path prefixes
	// e.g. ['dir.game'] additional_flags = "-Igame"
	// matches any file under the game/ directory
	mut rel_path := os.real_path(path)
	// Make path relative to project folder
	if rel_path.starts_with(c2v.project_folder + '/') {
		rel_path = rel_path[c2v.project_folder.len + 1..]
	} else if rel_path.starts_with('./') {
		rel_path = rel_path[2..]
	}
	// Check each directory component
	parts := rel_path.split('/')
	for i in 0 .. parts.len - 1 {
		dir_name := parts[0..i + 1].join('/')
		dir_flags := c2v.conf.value("'dir.${dir_name}'.additional_flags").default_to('').string()
		if dir_flags != '' {
			c2v.file_additional_flags += ' ' + dir_flags
		}
	}
}

fn get_pkg_config_cflags(pkg string) string {
	res := os.execute('pkg-config --cflags ${os.quoted_path(pkg)}')
	if res.exit_code != 0 {
		eprintln('The project uses the `${pkg}` pkg-config package, but `pkg-config --cflags ${pkg}` failed:')
		eprintln(res.output)
		exit(1)
	}
	return res.output.trim_space()
}

fn get_sdl_cflags() string {
	res := os.execute('sdl2-config --cflags')
	if res.exit_code != 0 {
		eprintln('The project uses sdl, but `sdl2-config` was not found. Try installing a development package for SDL2')
		exit(1)
	}
	return res.output.trim_space()
}
