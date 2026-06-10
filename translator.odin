package kolori

import mp "math-parser"
import "core:strings"
import "core:slice"
import "core:fmt"
import "core:log"

Translation_Error :: enum {
	None,
	UnknownVariable,
	WrongArity,
}

Error_Report :: struct {
	error: Translation_Error,
	msg: string
}

@(rodata)
funcs := []string {
	"real",
	"re",
	"imag",
	"im",
	"abs",
	"mod",
	"modulus",
	"norm",
	"arg",
	"phase",
	"conj",
	"proj", // "polar", "cis",
	"exp",
	"log",
	"ln",
	"log2",
	"log10",
	"logbase",
	"pow",
	"sqrt",
	"cbrt",
	"sin",
	"cos",
	"tan",
	"asin",
	"acos",
	"atan",
	"sinh",
	"cosh",
	"tanh",
	"asinh",
	"acosh",
	"atanh",
	"logbase",
}

@(rodata)
binary_funcs := []string{"logbase"}

expr_to_glsl :: proc(expr: mp.Expression) -> (str: string, err: Maybe(Error_Report)) {
	func_names := [mp.BinaryType]string {
		.Addition       = "c_add",
		.Subtraction    = "c_sub",
		.Multiplication = "c_mul",
		.Division       = "c_div",
		.Exponentiation = "c_pow",
	}

	switch expr in expr {
	case ^mp.Real:
		return fmt.tprintf("(vec2(%s,0))", expr.num), nil
	case ^mp.Variable:
		switch expr.name {
		case "z":
			return "z", nil
		case "t":
			return "(vec2(time,0))", nil
		case "i":
			return "I", nil
		case "e":
			return "E", nil
		case "pi":
			return "PI", nil
		case "tau":
			return "TAU", nil
		case "phi":
			return "PHI", nil
		case:
			err = Error_Report{
				error = .UnknownVariable,
				msg = fmt.tprintf("Unknown variable \"%s\"", expr.name)
			}

			return "", err
		}
	case ^mp.Binary:
		return fmt.tprintf(
			"%s(%s, %s)",
			func_names[expr.operation],
			expr_to_glsl(expr.left) or_return,
			expr_to_glsl(expr.right) or_return,
		), nil
	case ^mp.FunctionCall:
		expected_arity := slice.contains(binary_funcs, expr.name) ? 2 : 1
		if len(expr.arguments) != expected_arity {
			err = Error_Report{
				error = .WrongArity,
				msg = fmt.tprintf("Wrong arity for function \"%s\"", expr.name)
			}

			return "", err
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

		return strings.to_string(builder), nil
	case ^mp.Unary:
		return fmt.tprintf("-%s", expr_to_glsl(expr.inner) or_return), nil
	}

	return
}

translate_string :: proc(source: string) -> (string, bool) #optional_ok {
	expr, errors := mp.parse(source, funcs, {.Source_Nil_Terminated, .Implicit_Multiplication})
	defer mp.expression_free(expr)
	for err in errors {
		return err.msg, false
	}
	
	glsl, err := expr_to_glsl(expr)
	if err != nil {
		return err.?.msg, false
	} 

	result := fmt.tprintf("vec2 f(vec2 z) {{ return %s; }}", glsl)
	log.debug("generated glsl:", result)

	return result, true
}

translate_slice :: proc(source: []u8) -> (string, bool) #optional_ok {
	return translate_string((string)(source))
}

translate :: proc {
	translate_string,
	translate_slice
}