module main

import os

// 128-bit integers.
//
// V has no 128-bit integer type. C's `__int128` and `unsigned __int128` are
// translated to the two-word struct `C2vU128` (two's complement, the same
// layout as the C type on little-endian targets) and their operators to the
// helper functions below.

const int128_helpers_source = '// 128-bit integers (C `__int128`)
struct C2vU128 {
mut:
	lo u64
	hi u64
}

fn c2v_u128(v u64) C2vU128 {
	return C2vU128{
		lo: v
	}
}

fn c2v_i128(v i64) C2vU128 {
	return C2vU128{
		lo: u64(v)
		hi: if v < 0 { max_u64 } else { 0 }
	}
}

fn c2v_u128_add(a C2vU128, b C2vU128) C2vU128 {
	lo := a.lo + b.lo
	return C2vU128{
		lo: lo
		hi: a.hi + b.hi + (if lo < a.lo { u64(1) } else { u64(0) })
	}
}

fn c2v_u128_sub(a C2vU128, b C2vU128) C2vU128 {
	return C2vU128{
		lo: a.lo - b.lo
		hi: a.hi - b.hi - (if a.lo < b.lo { u64(1) } else { u64(0) })
	}
}

fn c2v_mul_64(x u64, y u64) C2vU128 {
	x0 := x & 0xffffffff
	x1 := x >> 32
	y0 := y & 0xffffffff
	y1 := y >> 32
	w0 := x0 * y0
	t := x1 * y0 + (w0 >> 32)
	w1 := (t & 0xffffffff) + x0 * y1
	return C2vU128{
		lo: x * y
		hi: x1 * y1 + (t >> 32) + (w1 >> 32)
	}
}

fn c2v_u128_mul(a C2vU128, b C2vU128) C2vU128 {
	p := c2v_mul_64(a.lo, b.lo)
	return C2vU128{
		lo: p.lo
		hi: p.hi + a.lo * b.hi + a.hi * b.lo
	}
}

fn c2v_u128_and(a C2vU128, b C2vU128) C2vU128 {
	return C2vU128{
		lo: a.lo & b.lo
		hi: a.hi & b.hi
	}
}

fn c2v_u128_or(a C2vU128, b C2vU128) C2vU128 {
	return C2vU128{
		lo: a.lo | b.lo
		hi: a.hi | b.hi
	}
}

fn c2v_u128_xor(a C2vU128, b C2vU128) C2vU128 {
	return C2vU128{
		lo: a.lo ^ b.lo
		hi: a.hi ^ b.hi
	}
}

fn c2v_u128_not(a C2vU128) C2vU128 {
	return C2vU128{
		lo: ~a.lo
		hi: ~a.hi
	}
}

fn c2v_u128_neg(a C2vU128) C2vU128 {
	return c2v_u128_add(c2v_u128_not(a), c2v_u128(1))
}

fn c2v_u128_shl(a C2vU128, n int) C2vU128 {
	s := n & 127
	if s == 0 {
		return a
	}
	if s >= 64 {
		return C2vU128{
			hi: a.lo << (s - 64)
		}
	}
	return C2vU128{
		lo: a.lo << s
		hi: (a.hi << s) | (a.lo >> (64 - s))
	}
}

fn c2v_u128_shr(a C2vU128, n int) C2vU128 {
	s := n & 127
	if s == 0 {
		return a
	}
	if s >= 64 {
		return C2vU128{
			lo: a.hi >> (s - 64)
		}
	}
	return C2vU128{
		lo: (a.lo >> s) | (a.hi << (64 - s))
		hi: a.hi >> s
	}
}

// Arithmetic shift of a signed value.
fn c2v_i128_shr(a C2vU128, n int) C2vU128 {
	s := n & 127
	if s == 0 {
		return a
	}
	sign_bits := if i64(a.hi) < 0 { max_u64 } else { u64(0) }
	if s >= 64 {
		return C2vU128{
			lo: u64(i64(a.hi) >> (s - 64))
			hi: sign_bits
		}
	}
	return C2vU128{
		lo: (a.lo >> s) | (a.hi << (64 - s))
		hi: u64(i64(a.hi) >> s)
	}
}

fn c2v_u128_cmp(a C2vU128, b C2vU128) int {
	if a.hi != b.hi {
		return if a.hi < b.hi { -1 } else { 1 }
	}
	if a.lo != b.lo {
		return if a.lo < b.lo { -1 } else { 1 }
	}
	return 0
}

fn c2v_i128_cmp(a C2vU128, b C2vU128) int {
	if a.hi != b.hi {
		return if i64(a.hi) < i64(b.hi) { -1 } else { 1 }
	}
	if a.lo != b.lo {
		return if a.lo < b.lo { -1 } else { 1 }
	}
	return 0
}

fn c2v_u128_is_zero(a C2vU128) bool {
	return a.lo == 0 && a.hi == 0
}

fn c2v_u128_to_f64(a C2vU128) f64 {
	return f64(a.hi) * 18446744073709551616.0 + f64(a.lo)
}

fn c2v_i128_to_f64(a C2vU128) f64 {
	if i64(a.hi) < 0 {
		return -c2v_u128_to_f64(c2v_u128_neg(a))
	}
	return c2v_u128_to_f64(a)
}

'

fn mentions_int128(t AstJsonType) bool {
	return t.qualified.contains('int128') || t.desugared_qualified.contains('int128')
}

// int128_kind returns 1 for `unsigned __int128`, -1 for `__int128`, else 0.
fn int128_kind(t AstJsonType) int {
	for name in [t.desugared_qualified, t.qualified] {
		cleaned := name.replace('const ', '').replace('volatile ', '').trim_space()
		if cleaned in ['unsigned __int128', '__uint128_t'] {
			return 1
		}
		if cleaned in ['__int128', '__int128_t', 'signed __int128'] {
			return -1
		}
	}
	return 0
}

fn (mut c C2V) ensure_int128_helpers() {
	key := 'int128_helpers:${os.dir(c.outv)}'
	if key !in c.generated_declarations {
		c.generated_declarations[key] = true
		c.local_type_declarations << int128_helpers_source
	}
}

fn node_int128_kind(node Node) int {
	return int128_kind(AstJsonType{
		qualified: node_effective_type_name(node)
		desugared_qualified: node.ast_type.desugared_qualified
	})
}

// int128_expr emits expressions that produce or consume a 128-bit integer.
// Returns false when `node` does not involve one.
fn (mut c C2V) int128_expr(node &Node) bool {
	result_kind := int128_kind(node.ast_type)
	if (node.kindof(.implicit_cast_expr) || node.kindof(.c_style_cast_expr))
		&& node.inner.len == 1 {
		source := node.inner[0]
		source_kind := node_int128_kind(source)
		if result_kind == 0 && source_kind == 0 {
			return false
		}
		c.ensure_int128_helpers()
		match node.cast_kind {
			'IntegralCast' {
				if result_kind != 0 && source_kind != 0 {
					c.expr(source)
				} else if result_kind != 0 {
					source_type := c.resolve_type_alias(c.convert_type(node_effective_type_name(source)).name)
					if source_type in ['i8', 'i16', 'int', 'i32', 'i64', 'isize'] {
						c.gen('c2v_i128(i64(')
					} else {
						c.gen('c2v_u128(u64(')
					}
					c.expr(source)
					c.gen('))')
				} else {
					// Truncation keeps the low bits.
					target := c.convert_type(node.ast_type.qualified).name
					c.gen('${target}((')
					c.expr(source)
					c.gen(').lo)')
				}
			}
			'IntegralToBoolean' {
				c.gen('!c2v_u128_is_zero(')
				c.expr(source)
				c.gen(')')
			}
			'IntegralToFloating' {
				target := c.convert_type(node.ast_type.qualified).name
				helper := if source_kind < 0 { 'c2v_i128_to_f64' } else { 'c2v_u128_to_f64' }
				c.gen('${target}(${helper}(')
				c.expr(source)
				c.gen('))')
			}
			'LValueToRValue', 'NoOp' {
				c.expr(source)
			}
			else {
				c.verror('unsupported 128-bit integer conversion ${node.cast_kind} in ${c.cur_file}:${node.location.line}')
			}
		}
		return true
	}
	if node.kindof(.binary_operator) && node.inner.len == 2 && node.opcode !in ['=', ','] {
		lhs := node.inner[0]
		rhs := node.inner[1]
		lhs_kind := node_int128_kind(lhs)
		if lhs_kind == 0 && node_int128_kind(rhs) == 0 {
			return false
		}
		c.ensure_int128_helpers()
		op := node.opcode
		if op in ['==', '!=', '<', '>', '<=', '>='] {
			helper := if lhs_kind < 0 { 'c2v_i128_cmp' } else { 'c2v_u128_cmp' }
			c.gen('${helper}(')
			c.expr(lhs)
			c.gen(', ')
			c.expr(rhs)
			c.gen(') ${op} 0')
			return true
		}
		if op in ['&&', '||'] {
			return false
		}
		c.gen_int128_operation(op, lhs, rhs, result_kind)
		return true
	}
	if node.kindof(.compound_assign_operator) && node.inner.len == 2
		&& node_int128_kind(node.inner[0]) != 0 {
		c.ensure_int128_helpers()
		lhs := node.inner[0]
		c.expr(lhs)
		c.gen(' = ')
		c.gen_int128_operation(node.opcode.trim_right('='), lhs, node.inner[1], node_int128_kind(lhs))
		return true
	}
	if node.kindof(.unary_operator) && node.inner.len == 1 && result_kind != 0
		&& node.opcode in ['-', '~', '+'] {
		c.ensure_int128_helpers()
		match node.opcode {
			'-' { c.gen('c2v_u128_neg(') }
			'~' { c.gen('c2v_u128_not(') }
			else { c.gen('(') }
		}
		c.expr(node.inner[0])
		c.gen(')')
		return true
	}
	if node.kindof(.unary_operator) && node.opcode == '!' && node.inner.len == 1
		&& node_int128_kind(node.inner[0]) != 0 {
		c.ensure_int128_helpers()
		c.gen('c2v_u128_is_zero(')
		c.expr(node.inner[0])
		c.gen(')')
		return true
	}
	return false
}

fn (mut c C2V) gen_int128_operation(op string, lhs Node, rhs Node, kind int) {
	helper := match op {
		'+' { 'c2v_u128_add' }
		'-' { 'c2v_u128_sub' }
		'*' { 'c2v_u128_mul' }
		'&' { 'c2v_u128_and' }
		'|' { 'c2v_u128_or' }
		'^' { 'c2v_u128_xor' }
		'<<' { 'c2v_u128_shl' }
		'>>' {
			if kind < 0 { 'c2v_i128_shr' } else { 'c2v_u128_shr' }
		}
		else { '' }
	}
	if helper == '' {
		c.verror('unsupported 128-bit integer operator `${op}` in ${c.cur_file}')
		return
	}
	c.gen('${helper}(')
	c.expr(lhs)
	c.gen(', ')
	if op in ['<<', '>>'] {
		c.gen('int(')
		c.expr(rhs)
		c.gen(')')
	} else {
		c.expr(rhs)
	}
	c.gen(')')
}
