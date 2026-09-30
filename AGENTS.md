This project is a C-to-V translator.

Always run project commands from the repository root:
the directory containing `v.mod` and `c2v.v`.

# Instruction Priority
If instructions conflict, follow them in this order:
1. System/developer/user instructions from the active session.
2. This `AGENTS.md` file.

# Prerequisites
Verify required tools before build/test commands:
1. `v version`
2. `cc --version` (or `clang --version`)

If either tool is missing, stop and report the missing dependency.

# Canonical Commands
1. Build: `v .`
2. Run one C test file: `v run tests/run_tests.vsh tests/ptr_deref.c`
3. Run all tests: `v run tests/run_tests.vsh`
4. Format translator sources only:
   `v fmt -w c2v.v comments.v configuration.v cpp.v external.v int128.v modules.v node.v node_kind.v split.v struct.v`

# Machine-Checkable Success Signals
- Build succeeds when `v .` exits with code `0`.
- Single-test succeeds when command exits with `0` and output contains no `FAIL`.
- Full test run succeeds when command exits with `0` and output contains no `FAIL`.
- Formatting succeeds when the translator source format command exits with code `0`.

# Runtime Guidance
- Build and single-test are the default validation loop.
- Full test run is slower; run it before finishing substantial code changes.
- The test runner rebuilds `c2v` and formats generated `tests/*.v` files during execution.

# Do Not
- Do not run project commands from subdirectories.
- Do not run single-test mode with non-`tests/*.c` paths.
- Do not format generated outputs under `tests/c2v_output/` unless explicitly requested.
- Do not format unrelated files outside the translator source list unless explicitly requested.

# Troubleshooting
- Wrong folder: run `pwd` and ensure it is the repository root containing `v.mod` and `c2v.v`.
- `v` not found: verify with `v version`.
- C compiler not found: verify with `cc --version` or `clang --version`.
- Single-test path issues: pass a `.c` file under `tests/`, for example `tests/ptr_deref.c`.
- If output is noisy, check command exit code first; non-zero exit means failure.

# Pre-PR Checklist
Run the Canonical Commands in order:
1. Build.
2. Single test (`tests/ptr_deref.c`).
3. Full test suite.
4. Format translator sources.
