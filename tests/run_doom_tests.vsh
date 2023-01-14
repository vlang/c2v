// Copyright (c) 2022 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can
// be found in the LICENSE file.
import term
import os
import runtime

struct App {
mut:
	idx atomic int
}

const files = [
	'g_game',
	'd_main',
	'm_menu',
	'p_enemy'
	//'wi_stuff'
	'p_saveg'
	//'st_stuff',
	'p_spec',
	'p_map',
	'am_map',
	'r_things',
	'r_draw',
	'p_mobj',
	'r_segs',
	'r_data',
	'p_setup',
	'p_pspr',
	'p_maputl',
	'p_inter',
	's_sound',
	'r_main',
	'p_switch',
	'hu_stuff',
	'statdump',
	'r_plane',
	'r_bsp',
	'p_sight',
	'p_floor',
	'deh_bexstr',
	'st_lib'
	//'sounds',
	'p_user',
	'p_plats',
	'p_lights',
	'hu_lib',
	'f_wipe',
	'r_sky',
	'p_tick',
	'p_telept',
	'm_random',
	'dstrings',
	'doomdef'
	//'deh_weapon.,
	//'deh_thing.c,
	//'deh_sound.c,
	//'deh_ptr.c / deh_frame.c,
	//'deh_doom.c,
	//'deh_cheat.c,
	//'deh_ammo.c,
	'd_items',
]

const (
	exe       = executable()
	tests_dir = dir(exe)
	c2v_dir   = dir(tests_dir)
	doom_dir  = join_path(dir(c2v_dir), 'doom')

	src_dir   = join_path(doom_dir, 'src/doom')
)

fn main() {
	println(src_dir)

	mut app := &App{
		idx: 0
	}

	for file in files {
		app.run(0)
	}
	/*
	nr_cpus := runtime.nr_cpus()
	mut threads := []thread{}
	for x in 0 .. nr_cpus {
		threads << go app.run(x)
	}
	threads.wait()
	*/
	println(term.green('ALL GOOD'))
}

fn (mut app App) run(x int) {
	if app.idx >= files.len {
		return
	}
	file := files[app.idx]
	app.idx++
	// for file in files {
	println('\nTranslating ${file}... (thread ${x})')
	cmd := 'v run ${c2v_dir}/tools/build_doom_file.vsh doom/${file}'
	ret := os.system('${cmd} > /dev/null')
	if ret != 0 {
		println(term.red('FAILED'))
		os.system(cmd) // re-run it to print the error
		exit(1)
	}
	println(term.green('OK'))
	//}
}
