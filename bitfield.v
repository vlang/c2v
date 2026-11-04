module main

import os

// Bit-fields in wrappers.
//
// V has no bit-fields. A translated program owns its records, so c2v gives
// each bit-field a whole field there. A wrapper, though, describes records
// of a C library compiled on its own, and its fields must be where the C
// compiler put them. Clang's JSON AST marks bit-fields but has no offsets, so
// for a wrapper c2v asks Clang for the record layouts, keeps the bytes of each
// run of bit-fields in plain integer fields, and gives each bit-field a getter
// and a setter (`r.flags()`, `r.set_flags(3)`).

// RecordLayout is a record as Clang lays it out.
struct RecordLayout {
	size   int
	align  int
	fields []LayoutField // the record's own fields, in declaration order
}

// LayoutField is a field of a RecordLayout. A bit-field occupies bits
// `bit .. bit + width - 1` counted from bit 0 of byte `offset`.
struct LayoutField {
	name        string // '' for an unnamed bit-field or an anonymous member
	offset      int
	is_bitfield bool
	bit         int
	width       int // 0 for `int : 0`
}

// BitfieldPlan says how record_decl emits a record that has bit-fields.
struct BitfieldPlan {
mut:
	align   int
	storage map[int][]string    // index of the first bit-field of a run in node.inner => the V fields that hold the run
	fields  map[int]LayoutField // index of each bit-field in node.inner => where it is
}

// record_layout_key names a record the way both the layout dump and the AST
// can: by its name, or by where an unnamed one is defined.
fn record_layout_key(name string, path string, offset int) string {
	if name != '' {
		return 'name:${name}'
	}
	real := os.real_path(path)
	return 'at:${if real == '' { path } else { real }}:${offset}'
}

// unnamed_record_location returns the `file:line:col` of a Clang type or
// record header such as `struct Outer::(unnamed at a.h:2:16)`.
fn unnamed_record_location(text string) ?string {
	for marker in ['(unnamed at ', '(anonymous at ', '(unnamed struct at ', '(unnamed union at ',
		'(anonymous struct at ', '(anonymous union at '] {
		if text.contains(marker) {
			return text.all_after(marker).all_before(')')
		}
	}
	return none
}

// location_key turns a `file:line:col` location into a record_layout_key.
fn location_key(location string, mut sources map[string][]string) ?string {
	parts := location.split(':')
	if parts.len < 3 {
		return none
	}
	path := parts[..parts.len - 2].join(':')
	line := parts[parts.len - 2].int()
	col := parts[parts.len - 1].int()
	if line < 1 || col < 1 {
		return none
	}
	if path !in sources {
		sources[path] = (os.read_file(path) or { return none }).split('\n')
	}
	lines := sources[path]
	if line > lines.len {
		return none
	}
	mut offset := 0
	for i in 0 .. line - 1 {
		offset += lines[i].len + 1
	}
	return record_layout_key('', path, offset + col - 1)
}

// parse_record_layouts reads the output of `-fdump-record-layouts-complete`.
fn parse_record_layouts(layout_dump string) map[string]RecordLayout {
	mut layouts := map[string]RecordLayout{}
	mut sources := map[string][]string{}
	lines := layout_dump.split_into_lines()
	mut i := 0
	for i < lines.len {
		if !lines[i].contains('*** Dumping AST Record Layout') {
			i++
			continue
		}
		i++
		for i < lines.len && !lines[i].contains('|') {
			i++
		}
		if i >= lines.len {
			break
		}
		header := lines[i].all_after('|').trim_space()
		i++
		mut fields := []LayoutField{}
		mut size := -1
		mut align := -1
		for i < lines.len && !lines[i].contains('*** Dumping AST Record Layout') {
			line := lines[i]
			i++
			if !line.contains('|') {
				continue
			}
			position := line.all_before('|').trim_space()
			text := line.all_after('|')
			if text.trim_space().starts_with('[sizeof=') {
				for entry in text.trim_space().trim('[]').split(', ') {
					if entry.starts_with('sizeof=') {
						size = entry.all_after('=').int()
					} else if entry.starts_with('align=') {
						align = entry.all_after('=').int()
					}
				}
				break
			}
			// After the `|`, the record's own fields are indented by three
			// spaces; the fields of a member record shown inside it, by more.
			if !text.starts_with('   ') || text.starts_with('    ') {
				continue
			}
			name := if text.ends_with(' ') { '' } else { text.all_after_last(' ') }
			if position.contains(':') {
				byte_offset := position.all_before(':').int()
				bits := position.all_after(':')
				if bits == '-' {
					fields << LayoutField{
						name:        name
						offset:      byte_offset
						is_bitfield: true
					}
				} else {
					first := bits.all_before('-').int()
					last := bits.all_after('-').int()
					fields << LayoutField{
						name:        name
						offset:      byte_offset
						is_bitfield: true
						bit:         first
						width:       last - first + 1
					}
				}
			} else {
				fields << LayoutField{
					name:   name
					offset: position.int()
				}
			}
		}
		if size < 0 || align < 0 {
			continue
		}
		key := if location := unnamed_record_location(header) {
			location_key(location, mut sources) or { continue }
		} else {
			record_layout_key(header.all_after(' ').trim_space(), '', 0)
		}
		layouts[key] = RecordLayout{
			size:   size
			align:  align
			fields: fields
		}
	}
	return layouts
}

// wrapper_record_layouts returns the record layouts of the header being
// wrapped. Clang is asked once, the first time a record needs them.
fn (mut c C2V) wrapper_record_layouts() map[string]RecordLayout {
	if c.record_layouts_loaded {
		return c.wrapper_layouts
	}
	c.record_layouts_loaded = true
	cmd := '${clang_exe} ${c.wrapper_layout_flags} -w -Xclang -fdump-record-layouts-complete -fsyntax-only -fno-diagnostics-color -c ${os.quoted_path(c.wrapper_layout_path)}'
	args := os.split_args(cmd) or { return c.wrapper_layouts }
	res := os.exec(args)
	if res.exit_code != 0 {
		eprintln('c2v: warning: ${c.wrapper_layout_path}: Clang did not report record layouts (`-fdump-record-layouts-complete` needs Clang 15 or later); records with bit-fields keep a field per bit-field, which is not their C layout')
		return c.wrapper_layouts
	}
	c.wrapper_layouts = parse_record_layouts(res.output)
	return c.wrapper_layouts
}

// c_type_size returns the size of a C type that Clang spells `qual_type`, if
// it is a scalar, a pointer, an array of those, or a record laid out above.
fn c_type_size(qual_type string, layouts map[string]RecordLayout, mut sources map[string][]string) ?int {
	mut t := qual_type.trim_space()
	for qualifier in ['const ', 'volatile ', 'restrict '] {
		t = t.replace(qualifier, '')
	}
	t = t.trim_space()
	if t.ends_with(']') && !t.contains('(') {
		count := t.all_after_last('[').all_before(']').int()
		if count <= 0 {
			return none
		}
		element := c_type_size(t.all_before_last('['), layouts, mut sources)?
		return count * element
	}
	if t.ends_with('*') || t.contains('(*') {
		return int(sizeof(voidptr))
	}
	if location := unnamed_record_location(t) {
		key := location_key(location, mut sources)?
		layout := layouts[key] or { return none }
		return layout.size
	}
	if t.starts_with('struct ') || t.starts_with('union ') {
		layout := layouts[record_layout_key(t.all_after(' ').trim_space(), '', 0)] or {
			return none
		}
		return layout.size
	}
	if t.starts_with('enum ') {
		return 4
	}
	return match t {
		'char', 'signed char', 'unsigned char', '_Bool', 'bool' { 1 }
		'short', 'unsigned short', 'short int', 'unsigned short int' { 2 }
		'int', 'unsigned int', 'unsigned', 'signed', 'float' { 4 }
		'long', 'unsigned long', 'long int', 'unsigned long int' { c_long_size }
		'long long', 'unsigned long long', 'long long int', 'unsigned long long int', 'double' { 8 }
		else { none }
	}
}

// bitfield_storage returns V fields that cover the bytes `start .. end - 1`
// of a record, each at an offset that is a multiple of its size, none
// aligned more than the record.
fn bitfield_storage(start int, end int, record_align int, first_index int) []string {
	mut fields := []string{}
	mut pos := start
	for pos < end {
		mut size := 8
		for size > 1 && (pos % size != 0 || pos + size > end || size > record_align) {
			size /= 2
		}
		fields << 'c2v_bitfield_${first_index + fields.len} u${size * 8}'
		pos += size
	}
	return fields
}

// plan_bitfields decides how a wrapper record with bit-fields is emitted, or
// returns none (after a warning) if its layout is not known.
fn (mut c C2V) plan_bitfields(node &Node, v_name string) ?BitfieldPlan {
	layouts := c.wrapper_record_layouts()
	if layouts.len == 0 {
		return none
	}
	key := record_layout_key(node.name, c.node_source_path(node), node.location.offset)
	layout := layouts[key] or {
		eprintln('c2v: warning: ${c.cur_file}: no layout of `${v_name}` from Clang; its bit-fields are not at their C offsets')
		return none
	}
	// The record's fields, as the AST has them, are those of the layout.
	mut field_indexes := []int{}
	for i, field in node.inner {
		if field.kind == .field_decl {
			field_indexes << i
		}
	}
	if field_indexes.len != layout.fields.len {
		eprintln('c2v: warning: ${c.cur_file}: the layout of `${v_name}` from Clang does not match its fields; its bit-fields are not at their C offsets')
		return none
	}
	for n, i in field_indexes {
		if node.inner[i].name != layout.fields[n].name
			|| node.inner[i].is_bitfield != layout.fields[n].is_bitfield {
			eprintln('c2v: warning: ${c.cur_file}: the layout of `${v_name}` from Clang does not match its fields; its bit-fields are not at their C offsets')
			return none
		}
	}
	is_union := node.tags.contains('union')
	align := if record_is_packed(node) { 1 } else { layout.align }
	mut plan := BitfieldPlan{
		align: align
	}
	mut counter := 0
	if is_union {
		// All members start at 0: one array holds every bit-field.
		mut end := 0
		mut first := -1
		for n, i in field_indexes {
			f := layout.fields[n]
			if f.is_bitfield && f.width > 0 {
				end = int_max(end, f.offset + (f.bit + f.width + 7) / 8)
				if first < 0 {
					first = i
				}
				plan.fields[i] = f
			}
		}
		if first >= 0 {
			plan.storage[first] = ['c2v_bitfield_0 [${end}]u8']
		}
		return plan
	}
	mut sources := map[string][]string{}
	// Where the V fields emitted so far end, if known: V places the next one
	// at the first offset after it that suits its alignment.
	mut emitted_end := 0
	mut emitted_end_known := true
	mut previous_offset := 0
	mut n := 0
	for n < field_indexes.len {
		f := layout.fields[n]
		if !f.is_bitfield {
			field := node.inner[field_indexes[n]]
			type_name := if field.ast_type.desugared_qualified != '' {
				field.ast_type.desugared_qualified
			} else {
				field.ast_type.qualified
			}
			previous_offset = f.offset
			if size := c_type_size(type_name, layouts, mut sources) {
				emitted_end = f.offset + size
				emitted_end_known = true
			} else {
				emitted_end_known = false
			}
			n++
			continue
		}
		if f.width == 0 {
			n++
			continue
		}
		// A run of bit-fields, up to the next field that has storage.
		run_start := n
		mut start := f.offset + f.bit / 8
		for n < field_indexes.len && layout.fields[n].is_bitfield {
			g := layout.fields[n]
			if g.width > 0 {
				start = int_min(start, g.offset + g.bit / 8)
				plan.fields[field_indexes[n]] = g
			}
			n++
		}
		mut end := layout.size
		for m in n .. field_indexes.len {
			if !layout.fields[m].is_bitfield || layout.fields[m].width > 0 {
				end = layout.fields[m].offset + layout.fields[m].bit / 8
				break
			}
		}
		mut storage := []string{}
		if emitted_end_known && start < emitted_end {
			// The size of the previous field was taken to be larger than it is.
			eprintln('c2v: warning: ${c.cur_file}: cannot place the bit-fields of `${v_name}`; they are not at their C offsets')
			return none
		}
		if emitted_end_known {
			if start > emitted_end {
				storage << 'c2v_bitfield_pad_${counter} [${start - emitted_end}]u8'
			}
		} else {
			// The previous field ends somewhere after its first byte. The
			// first storage field lands at `start` only if its alignment
			// leaves no room for doubt.
			mut first_size := 8
			for first_size > 1 && (start % first_size != 0 || start + first_size > end
				|| first_size > align) {
				first_size /= 2
			}
			if start - (previous_offset + 1) >= first_size {
				eprintln('c2v: warning: ${c.cur_file}: cannot place the bit-fields of `${v_name}` after a field of unknown size; they are not at their C offsets')
				return none
			}
		}
		storage << bitfield_storage(start, end, align, counter)
		counter += storage.len
		plan.storage[field_indexes[run_start]] = storage
		emitted_end = end
		emitted_end_known = true
	}
	return plan
}

// bitfield_accessors returns a getter and a setter for the bit-field `f` of
// the record `record`, whose V name is `name` and V type `typ`.
fn (c &C2V) bitfield_accessors(record string, name string, typ string, f LayoutField) string {
	first_bit := f.offset * 8 + f.bit
	byte_offset := first_bit / 8
	shift := first_bit % 8
	n_bytes := (shift + f.width + 7) / 8
	if n_bytes > 8 {
		return '// `${name}` spans more than 8 bytes: no accessors.\n'
	}
	signed := typ in ['i8', 'i16', 'i32', 'i64', 'int', 'isize']
	is_bool := typ == 'bool'
	is_enum := typ in c.enums
	if !signed && !is_bool && !is_enum && typ !in ['u8', 'u16', 'u32', 'u64', 'usize'] {
		return '// `${name}` is a bit-field of type `${typ}`: no accessors.\n'
	}
	mask := if f.width >= 64 {
		'0xffffffffffffffff'
	} else {
		'0x' + ((u64(1) << f.width) - 1).hex()
	}
	at := if byte_offset == 0 { '' } else { ' + ${byte_offset}' }
	value := if signed {
		'${typ}(i64(bits << ${64 - shift - f.width}) >> ${64 - f.width})'
	} else if is_bool {
		'(bits >> ${shift}) & 1 != 0'
	} else if is_enum {
		'unsafe { ${typ}(int((bits >> ${shift}) & ${mask})) }'
	} else {
		'${typ}((bits >> ${shift}) & ${mask})'
	}
	raw := if is_bool {
		'(if value { u64(1) } else { u64(0) })'
	} else if is_enum {
		'u64(int(value))'
	} else {
		'u64(value)'
	}
	return 'pub fn (r &${record}) ${name}() ${typ} {
	mut bits := u64(0)
	unsafe { vmemcpy(&bits, &u8(r)${at}, ${n_bytes}) }
	return ${value}
}

pub fn (mut r ${record}) set_${name}(value ${typ}) {
	mut bits := u64(0)
	unsafe { vmemcpy(&bits, &u8(&r)${at}, ${n_bytes}) }
	mask := u64(${mask}) << ${shift}
	bits = (bits & ~mask) | ((${raw} << ${shift}) & mask)
	unsafe { vmemcpy(&u8(&r)${at}, &bits, ${n_bytes}) }
}
'
}
