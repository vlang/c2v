module main

import os
import toml

fn (mut c2v C2V) handle_configuration(args []string) {
	last_path := args.last()
	if os.is_dir(last_path) {
		c2v.is_dir = true
		c2v.project_folder = os.real_path(last_path)
	} else {
		c2v.is_dir = false
		c2v.project_folder = os.dir(os.real_path(last_path))
	}
	// Configuration file priority:
	// 1) C2V_CONFIG, but only if it exits
	// 2) project_folder/c2v.toml, but only if it exists
	mut c2v_config_file := os.getenv('C2V_CONFIG')
	if c2v_config_file == '' || !os.exists(c2v_config_file) {
		c2v_config_file = ''
		folder_file := os.join_path(c2v.project_folder, 'c2v.toml')
		if os.exists(folder_file) {
			c2v_config_file = folder_file
		}
	}
	c2v.read_toml_configuration(c2v_config_file)
	c2v.set_config_overrides_for_project()
}

fn (mut c2v C2V) get_additional_flags(path string) string {
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
	c2v.project_output_dirname = c2v.conf.value('project.output_dirname').default_to('c2v_output').string()
	c2v.project_additional_flags = c2v.conf.value('project.additional_flags').default_to('-I.').string()
	c2v.wrapper_module_name = c2v.conf.value('project.wrapper_module_name').default_to('').string()
	c2v.keep_ast = c2v.conf.value('keep_ast').default_to(false).bool()
	if c2v.project_uses_sdl {
		sdl_cflags := get_sdl_cflags()
		c2v.project_additional_flags += ' ' + sdl_cflags
	}
	c2v.project_globals_path = os.real_path(os.join_path(c2v.project_folder, c2v.project_output_dirname,
		'_globals.v'))
}

// called once per each .c file
fn (mut c2v C2V) set_config_overrides_for_file(path string) {
	fname := os.file_name(path)
	c2v.file_additional_flags = c2v.conf.value("'${fname}'.additional_flags").default_to('').string()
}

fn get_sdl_cflags() string {
	res := os.execute('sdl2-config --cflags')
	if res.exit_code != 0 {
		eprintln('The project uses sdl, but `sdl2-config` was not found. Try installing a development package for SDL2')
		exit(1)
	}
	return res.output.trim_space()
}
