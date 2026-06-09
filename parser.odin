package kolori

import "core:fmt"
import "core:slice"
import "core:strings"
import mp "math-parser"

TranslationError :: enum {
	None,
	UnknownVariable,
	WrongArity,
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

expr_to_opengl :: proc(expr: mp.Expression) -> (str: string, err: TranslationError) {
	func_names := [mp.BinaryOperationType]string {
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
			return "(vec2(t,0))", nil
		case "i":
			return "M_I", nil
		case "e":
			return "M_E", nil
		case "pi":
			return "M_PI", nil
		case "tau":
			return "M_TAU", nil
		case "phi":
			return "M_PHI", nil
		case:
			return expr.name, .UnknownVariable
		}
	case ^mp.BinaryOperation:
		return fmt.tprintf(
			"%s(%s, %s)",
			func_names[expr.operation],
			expr_to_opengl(expr.left) or_return,
			expr_to_opengl(expr.right) or_return,
		), nil
	case ^mp.FunctionCall:
		expected_arity := slice.contains(binary_funcs, expr.name) ? 2 : 1
		if len(expr.arguments) != expected_arity {
			return expr.name, .WrongArity
		}

		builder: strings.Builder
		strings.builder_init(&builder, context.temp_allocator)
		defer strings.builder_destroy(&builder)

		fmt.sbprintf(&builder, "c_%s", expr.name)
		fmt.sbprint(&builder, "(")
		fmt.sbprint(&builder, expr_to_opengl(expr.arguments[0]) or_return)
		for i in expr.arguments[1:] {
			fmt.sbprint(&builder, ",", expr_to_opengl(i) or_return)
		}
		fmt.sbprint(&builder, ")")

		return strings.to_string(builder), nil
	case ^mp.Unary:
		return fmt.tprintf("-%s", expr_to_opengl(expr.inner) or_return), nil
	}

	return
}

translate :: proc(source: string) -> (result: string, ok: bool) #optional_ok {
	scanner: mp.Scanner
	scanner.source = source
	scanner.functions = funcs
	defer mp.scanner_destroy(&scanner)


	mp.scanner_scan_tokens(&scanner)
	if len(scanner.errors) != 0 {
		for err in scanner.errors {
			bad_char := scanner.source[err.column - 1]
			return fmt.tprintf("Unexpected character '%c' at col %i", bad_char, err.column), false
		}
	}
	
	parser: mp.Parser
	parser.tokens = scanner.tokens[:]

	expr, err := mp.parser_parse(&parser)
	defer mp.expression_free(expr)
	if err != nil {
		col := mp.parser_peek(&parser).column
		switch err {
		case .ExpectedLParen:
			return fmt.tprintf("Expected '(' at column %i.", col), false
		case .ExpectedRParen:
			return fmt.tprintf("Expected ')' at column %i.", col), false
		case .UnexpectedToken:
			return fmt.tprintf(
				"Token '%s' unexpected at column %i.",
				scanner.tokens[parser.current].lexeme,
				col,
			), false
		case .UnexpectedEOF:
			return fmt.tprint("Incomplete expression."), false
		case .None:
			unreachable()
		}

		return
	}

	res, _err := expr_to_opengl(expr)
	switch _err {
	case .UnknownVariable:
		return fmt.tprintf("Unknown variable \"%s\"", res), false
	case .WrongArity:
		return fmt.tprintf("Wrong arity for function \"%s\"", res), false
	case .None:
		fmt.printfln("vec2 f(vec2 z) {{ return %s; }}", res)
		return fmt.tprintf("vec2 f(vec2 z) {{ return %s; }}", res), true
	}

	return

}
