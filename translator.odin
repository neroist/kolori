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
	"real",
	"re",
	"imag",
	"im",
	"abs",
	// until the parser is extended for the "%" operator
	"mod",
	"arg",
	"conj",
	"exp",
	"ln",
	"log",
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
	"gamma"
}

// functions that require two arguments
@(rodata)
binary_funcs := []string{"mod", "logbase"}

expr_to_glsl :: proc(expr: mp.Expression) -> (result: string, ok: bool = true)
{
	@(static)
	@(rodata)
	func_names := [mp.BinaryType]string {
		.Addition       = "c_add",
		.Subtraction    = "c_sub",
		.Multiplication = "c_mul",
		.Division       = "c_div",
		.Exponentiation = "c_pow",
	}

	switch expr in expr {
	case ^mp.Real:
		result = fmt.tprintf("vec2(%s, 0)", expr.num)
	case ^mp.Variable:
		switch expr.name {
		case "z":
			result = "z"
		case "t":
			result = "vec2(time, 0)"
		case "i":
			result = "C_I"
		case "e":
			result = "C_E"
		case "pi", "π":
			result = "C_PI"
		case "tau", "τ":
			result = "C_TAU"
		case "phi", "φ", "ϕ":
			result = "C_PHI"
		case:
			ok = false
			result = fmt.tprintf("Unknown variable \"%s\"", expr.name)
		}
	case ^mp.Binary:
		result = fmt.tprintf(
			"%s(%s, %s)",
			func_names[expr.operation],
			expr_to_glsl(expr.left) or_return,
			expr_to_glsl(expr.right) or_return,
		)
	case ^mp.FunctionCall:
		expected_arity := slice.contains(binary_funcs, expr.name) ? 2 : 1
		if len(expr.arguments) != expected_arity {
			ok = false
			result = fmt.tprintf("Wrong arity for function \"%s\"", expr.name)
		}

		builder: strings.Builder
		strings.builder_init(&builder, context.temp_allocator)
		defer strings.builder_destroy(&builder)

		fmt.sbprintf(&builder, "c_%s", expr.name)
		fmt.sbprint(&builder, "(")
		fmt.sbprint(&builder, expr_to_glsl(expr.arguments[0]) or_return)
		for i in expr.arguments[1:] {
			fmt.sbprint(&builder, ",", expr_to_glsl(i) or_return)
		}
		fmt.sbprint(&builder, ")")

		result = strings.to_string(builder)
	case ^mp.Unary:
		result = fmt.tprintf("-%s", expr_to_glsl(expr.inner) or_return)
	}

	return result, ok
}

validate_expr :: proc(expr: mp.Expression) -> (Maybe(string))
{
	switch expr in expr {
	case ^mp.Variable:
		switch expr.name {
		case "z", "t", "i", "e", "pi", "π", "tau", "τ", "phi", "φ", "ϕ":
			/* */
		case:
			return fmt.aprintf("Unknown variable \"%s\"", expr.name)
		}
	case ^mp.Binary:
		if validate_expr(expr.left) == nil {
			return validate_expr(expr.right)
		}
	case ^mp.FunctionCall:
		expected_arity := slice.contains(binary_funcs, expr.name) ? 2 : 1
		if len(expr.arguments) != expected_arity {
			return fmt.aprintf("Wrong arity for function \"%s\"", expr.name)
		}

		for i in expr.arguments {
			if err := validate_expr(i); err == nil {
				return err
			}
		}
	case ^mp.Unary:
		return validate_expr(expr.inner)
	case ^mp.Real:
		return nil
	}

	return nil
}

validate_string :: proc(source: string) -> (Maybe(string))
{
	expr, reports := mp.parse(source, funcs, {.Source_Nil_Terminated, .Implicit_Multiplication}, context.temp_allocator)
	defer mp.expression_free(expr, context.temp_allocator)

	if len(reports) > 0 {
		err_msg_builder: strings.Builder
		strings.builder_init(&err_msg_builder, context.temp_allocator)
		
		for report in reports {
			fmt.sbprintln(&err_msg_builder, report.msg)
		}

		return strings.to_string(err_msg_builder)
	}
	
	return validate_expr(expr)
}

validate_slice :: proc(source: []u8) -> (Maybe(string))
{
	return validate_string((string)(source))
}

validate :: proc {
	validate_string,
	validate_slice,
	validate_expr
}

translate_string :: proc(source: string) -> (string, bool) #optional_ok
{
	expr, reports := mp.parse(source, funcs, {.Source_Nil_Terminated, .Implicit_Multiplication}, context.temp_allocator)
	defer mp.expression_free(expr, context.temp_allocator)

	if len(reports) > 0 {
		err_msg_builder: strings.Builder
		strings.builder_init(&err_msg_builder, context.temp_allocator)
		
		for report in reports {
			fmt.sbprintln(&err_msg_builder, report.msg)
		}

		return strings.to_string(err_msg_builder), false
	}
	
	result, ok := expr_to_glsl(expr)
	if !ok {
		return result, false
	} 

	result = fmt.tprintf("vec2 f(vec2 z) {{ return %s; }}", result)
	log.debug("generated glsl:", result)

	return result, true
}

translate_slice :: proc(source: []u8) -> (string, bool) #optional_ok
{
	return translate_string((string)(source))
}

translate :: proc {
	translate_string,
	translate_slice
}

@(test)
test_translator :: proc (t: ^testing.T)
{
	inp_to_outp := map[string]string{
		"z\x00" =         "vec2 f(vec2 z) { return z; }",
		"z+1\x00" =       "vec2 f(vec2 z) { return c_add(z, vec2(1, 0)); }",
		"z^(t - 1)\x00" = "vec2 f(vec2 z) { return c_pow(z, c_sub(vec2(time, 0), vec2(1, 0))); }"
	}

	for inp, outp in inp_to_outp {
		testing.expect(t, translate(inp) == outp)
	}
}