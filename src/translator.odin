#+feature dynamic-literals

package kolori

// todo(functions) add sum and product functions?

import mp "math-parser"
import "core:strings"
import "core:testing"
import "core:slice"
import "core:fmt"
import "core:log"

// functions supported by kolori
@(rodata)
funcs := []string {
	"gamma",
	"floor",
	"ceil",
	"frac",
	"trunc",
	"real",
	"re", // synonym for "real"
	"imag",
	"im", // synonym for "imag"
	"abs",
	"mod", // you may also use the "%" operator
	"arg",
	"conj",
	"exp",
	"ln",
	"log", // synonym for "ln"
	"log2",
	"log10",
	"logbase",
	"sqrt",
	"cbrt",
	"sin",
	"cos",
	"tan",
	"csc",
	"sec",
	"cot",
	"asin",
	"acos",
	"atan",
	"acsc",
	"asec",
	"acot",
	"sinh",
	"cosh",
	"tanh",
	"csch",
	"sech",
	"coth",
	"asinh",
	"acosh",
	"atanh",
	"acsch",
	"asech",
	"acoth",
}

// functions that require two arguments
@(rodata)
binary_funcs := []string{"mod", "logbase"}

@(private = "file")
translate_expr :: proc(expr: mp.Expression) -> string 
{
	@(static, rodata)
	func_names := [mp.BinaryType]string {
		.Addition       = "c_add",
		.Subtraction    = "c_sub",
		.Multiplication = "c_mul",
		.Division       = "c_div",
		.Exponentiation = "c_pow",
		.Modulo         = "c_mod",
	}

	switch expr in expr {
	case ^mp.Real:
		return fmt.tprintf("vec2(%s, 0)", expr.num)
	case ^mp.Variable:
		switch expr.name {
		case "z":
			return "z"
		case "t":
			return "vec2(time, 0)"
		case "i":
			return "C_I"
		case "e":
			return "C_E"
		case "pi", "π":
			return "C_PI"
		case "tau", "τ":
			return "C_TAU"
		case "phi", "φ", "ϕ":
			return "C_PHI"
		case:
			// this function is only called after using `validate()`.
			// this should ensure that there are no errors, thus we 
			// should never be able to reach this case block.
			unreachable()
		}
	case ^mp.Binary:
		return fmt.tprintf(
			"%s(%s, %s)",
			func_names[expr.operation],
			translate_expr(expr.left),
			translate_expr(expr.right),
		)
	case ^mp.FunctionCall:
		builder: strings.Builder
		strings.builder_init(&builder, context.temp_allocator)

		strings.write_string(&builder, "c_")
		strings.write_string(&builder, expr.name)
		strings.write_string(&builder, "(")
		strings.write_string(&builder, translate_expr(expr.arguments[0]))
		for i in expr.arguments[1:] {
			strings.write_string(&builder, ", ")
			strings.write_string(&builder, translate_expr(i))
		}
		strings.write_string(&builder, ")")

		return strings.to_string(builder)
	case ^mp.Unary:
		return fmt.tprintf("-%s", translate_expr(expr.inner))
	}

	// since odin asks me to add a return here
	unreachable()
}

validate_expr :: proc(expr: mp.Expression) -> Maybe(cstring) 
{
	switch expr in expr {
	case ^mp.Variable:
		switch expr.name {
		case "z", "t", "i", "e", "pi", "π", "tau", "τ", "phi", "φ", "ϕ":
			return nil
		case:
			// in case of an error, we will need to persist these error
			// messages to display in the ui. so, we don't use the temporary
			// allocator here. instead, we free them whenever we don't need
			// them anymore 
			return fmt.caprintf("Unknown variable \"%s\"", expr.name)
		}
	case ^mp.Binary:
		if err := validate_expr(expr.left); err != nil {
			return err
		}

		return validate_expr(expr.right)
	case ^mp.FunctionCall:
		expected_arity := slice.contains(binary_funcs, expr.name) ? 2 : 1
		if len(expr.arguments) != expected_arity {
			return fmt.caprintf("Wrong arity for function \"%s\"", expr.name)
		}

		for i in expr.arguments {
			if err := validate_expr(i); err != nil {
				return err
			}
		}

		return nil
	case ^mp.Unary:
		return validate_expr(expr.inner)
	case ^mp.Real:
		return nil
	}

	unreachable()
}

validate :: proc(source: cstring) -> Maybe(cstring) 
{
	// issue in the odin compiler:
	//
	// `cast` is needed here else we get a "Missing type in compound literal"
	// error for the bitset
	expr, reports := mp.parse(
		cast(string)(source),
		funcs,
		{.Implicit_Multiplication},
		context.temp_allocator,
	)

	if len(reports) > 0 {
		err_msg := strings.clone_to_cstring(reports[0].msg)
		// delete(reports)
		return err_msg
	}

	return validate_expr(expr)
}

translate :: proc(source: cstring, func_name := "f") -> cstring 
{
	expr :=
		mp.parse(
			cast(string)(source),
			funcs,
			{.Implicit_Multiplication},
			context.temp_allocator,
		) or_else unreachable()

	glsl := fmt.ctprintf(
		"vec2 %s(vec2 z) {{ return %s; }}",
		func_name,
		translate_expr(expr),
	)
	log.debug("generated glsl:", glsl)
	return glsl
}

@(test)
test_translator :: proc(t: ^testing.T) 
{
	inp_to_outp := map[cstring]cstring {
		"z"         = "vec2 f(vec2 z) { return z; }",
		"z+1"       = "vec2 f(vec2 z) { return c_add(z, vec2(1, 0)); }",
		"z^(t - 1)" = "vec2 f(vec2 z) { return c_pow(z, c_sub(vec2(time, 0), vec2(1, 0))); }",
	}

	for inp, outp in inp_to_outp {
		testing.expect(t, translate(inp) == outp)
	}
}
