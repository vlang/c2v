# Translating Doom 3 to V

This directory holds the c2v project files that translate the Doom 3 engine
and base game ([dhewm3](https://github.com/dhewm/dhewm3), C++) into one V
program. The dhewm3 sources are used unmodified: 277 C++ files become 277 V
files in a single module, which V builds into one executable that plays the
Doom 3 demo.

Validated on macOS arm64 only (the paths and defines in `c2v.toml` and
`config.h` are for that platform).

| File                     | Purpose                                                    |
|--------------------------|------------------------------------------------------------|
| `c2v.toml`               | project configuration (include paths, defines, link flags) |
| `c2v-target-sources.txt` | the C++ files to translate                                 |
| `c2v-native-sources.txt` | C files compiled as C and linked (stb, miniz)              |
| `config.h`               | the header CMake would generate for a native build         |
| `clang-opt`              | compiler wrapper for an optimized build                    |

## Requirements

- `clang` (Xcode command line tools).
- `brew install sdl2 openal-soft`
- V (validated with commit `04fc6a9`, 2026-10-01).
- c2v built from this repository with that V: `v .`
- About 8 GB of free memory for the translation.
- The Doom 3 demo data, `demo00.pk4` (see [Run](#4-run)).

## 1. Get dhewm3 and install the project files

```sh
git clone https://github.com/dhewm/dhewm3
cd dhewm3
git checkout 455b88e8        # 1.5.5
mkdir -p neo/c2v-mono neo/idlib/c2v-support
cp $C2V/examples/doom3/c2v.toml $C2V/examples/doom3/c2v-*-sources.txt neo/c2v-mono/
cp $C2V/examples/doom3/config.h neo/idlib/c2v-support/
```

`$C2V` is the c2v repository. The paths in the source lists are relative to
`neo/c2v-mono`.

## 2. Translate

```sh
cd neo/c2v-mono
GC_INITIAL_HEAP_SIZE=16G $C2V/c2v "$PWD"
```

This takes about 35 minutes and ends with `Translated 277 files`. The V
sources are written to `neo/c2v-mono/c2v_strict_output`: one file per C++
file, `0_globals.v` (globals and shared helpers) and `0_external.c.v`
(declarations of the C libraries used).

`GC_INITIAL_HEAP_SIZE` is needed: without it c2v's garbage collector aborts
with `Too many retries in GC_allocobj` on a project of this size. c2v runs
`v fmt` on its output, so `v` must be in `PATH`.

## 3. Build

```sh
ulimit -s 65520
v -old-compiler -g -message-limit -1 -cc $C2V/examples/doom3/clang-opt \
	-cflags '-ferror-limit=0' -o doom3 c2v_strict_output
```

`-old-compiler` is needed: V's new compiler does not accept the translated
C++ yet (it rejects, among other things, methods reached through more than one
embedded base and pointer upcasts). `ulimit -s` raises the stack limit for the
V compiler.

`clang-opt` compiles the generated C with `-O2 -ffp-contract=off`. V itself
uses `-O0` unless `-prod` is given, and `-prod` cannot be used here: it adds
garbage collector root registrations that overflow ("Too many root sets").
`-ffp-contract=off` matches the native dhewm3 build; fused multiply-adds
change floating point rounding, which the physics amplifies into visibly
different results. For an unoptimized build pass `-cc clang` instead.

## 4. Run

The game data is not part of dhewm3. The demo is enough: download
`doom3-linux-1.1.1286-demo.x86.run` and unpack it without running its
installer.

```sh
sh doom3-linux-1.1.1286-demo.x86.run --noexec --target doom3-demo
cp doom3-demo/demo/demo00.pk4 $DHEWM3/base/
```

`$DHEWM3` is the dhewm3 checkout (`fs_basepath` is the directory containing
`base/`).

```sh
./doom3 +set fs_basepath $DHEWM3 +set fs_savepath /tmp/doom3-v \
	+set fs_configpath /tmp/doom3-v +set r_fullscreen 0 \
	+map game/demo_mars_city1
```

Without `+map` the game opens its main menu. The demo has two more maps,
`game/demo_mc_underground` and `game/demo_mars_city2`.

Setting `fs_savepath` and `fs_configpath` keeps the configuration and
savegames apart from those of an installed dhewm3.

For a scripted run, put console commands in
`<fs_savepath>/base/autoexec.cfg`:

```
seta r_fullscreen 0
wait 20
map game/demo_mars_city1
wait 600
screenshot
quit
```

Add `+set com_fixedTic 1` to run the game logic at a fixed step per frame,
which makes runs comparable with each other and with a native dhewm3 build.

## The project configuration

```toml
[project]
output_dirname = "c2v_strict_output"
additional_flags = "-I../idlib ... -DD3_OSTYPE=\\\"macosx\\\" -DD3_ARCH=\\\"arm64\\\" ..."
uses_sdl = true
single_module = true
generate_stubs = false
require_no_stubs = true
require_main = true
source_manifest = "c2v-target-sources.txt"
native_source_manifest = "c2v-native-sources.txt"
link_flags = "-L/opt/homebrew/opt/openal-soft/lib -lopenal"
```

- `source_manifest` lists the files to translate, one per line, relative to
  the project directory. Without it c2v translates every file in the
  directory.
- `native_source_manifest` lists C files that are not translated: the V build
  compiles and links them as C.
- `single_module = true` puts all files in one V module, so that they share
  types and globals like the translation units of one C++ program.
- `generate_stubs = false` and `require_no_stubs = true` make the translation
  fail when a called function or a type has no translated definition, instead
  of generating a stub for it.
- `require_main = true` fails the translation if no `main` function was
  translated.
- `additional_flags` carries the include paths and the defines that CMake
  passes to a native build. `-DIMGUI_DISABLE` leaves out the Dear ImGui
  settings menu, which is a C++ library of its own.
- `uses_sdl` and `link_flags` link SDL2 and OpenAL.

For another platform, change the `-D` values and the Homebrew paths in
`c2v.toml`, the values in `config.h`, and the `sys/` entries of
`c2v-target-sources.txt` (the list uses dhewm3's portable SDL and POSIX
backends with `sys/linux/main.cpp`).

## Limitations

- Savegames are not interchangeable with native dhewm3: C++ bit-fields are
  translated to ordinary fields, so saved structures have a different layout.
  Saving and loading within the translated game works.
- The translated game uses more memory than the native one (about 1.6 GB
  against 1.3 GB in the first demo map) and its game code is about 20% slower.
- Destructors run for `delete`, but not for locals and temporaries: memory
  that only their destructor would release is not released.
