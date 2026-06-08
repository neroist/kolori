package vivi

import "core:fmt"
import "core:slice"
import "core:strings"
import mp "../math-parser"

ConversionError :: enum {
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

expr_to_opencl :: proc(expr: mp.Expression) -> (str: string, err: ConversionError) {
	func_names := [mp.BinaryOperationType]string {
		.Addition       = "cadd",
		.Subtraction    = "csub",
		.Multiplication = "cmul",
		.Division       = "cdiv",
		.Exponentiation = "cpow",
	}

	switch expr in expr {
	case ^mp.Real:
		return fmt.tprintf("(cmplx)(%s,0)", expr.num), nil
	case ^mp.Variable:
		switch expr.name {
		case "z":
			return "z", nil
		case "t":
			return "(cmplx)(t,0)", nil
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
			expr_to_opencl(expr.left) or_return,
			expr_to_opencl(expr.right) or_return,
		), nil
	case ^mp.FunctionCall:
		expected_arity := slice.contains(binary_funcs, expr.name) ? 2 : 1
		if len(expr.arguments) != expected_arity {
			return expr.name, .WrongArity
		}

		builder: strings.Builder
		strings.builder_init(&builder, context.temp_allocator)
		defer strings.builder_destroy(&builder)

		fmt.sbprintf(&builder, "c%s", expr.name)
		fmt.sbprint(&builder, "(")
		fmt.sbprint(&builder, expr_to_opencl(expr.arguments[0]) or_return)
		for i in expr.arguments[1:] {
			fmt.sbprint(&builder, ",", expr_to_opencl(i) or_return)
		}
		fmt.sbprint(&builder, ")")

		return strings.to_string(builder), nil
	case ^mp.Unary:
		return fmt.tprintf("-%s", expr_to_opencl(expr.inner) or_return), nil
	}

	return
}

main0 :: proc() {
	scanner: mp.Scanner
	scanner.source = "2x"
	scanner.functions = funcs
	defer mp.scanner_destroy(&scanner)

	parser: mp.Parser
	parser.tokens = scanner.tokens[:]

	mp.scanner_scan_tokens(&scanner)
	if len(scanner.errors) != 0 {
		for err in scanner.errors {
			bad_char := scanner.source[err.column - 1]
			fmt.eprintfln("Unexpected character '%c' at col %i", bad_char, err.column)
		}

		return
	}

	expr, err := mp.parser_parse(&parser)
	defer mp.expression_free(expr)
	if err != nil {
		col := mp.parser_peek(&parser).column
		switch err {
		case .ExpectedLParen:
			fmt.eprintfln("Expected '(' at column %i.", col)
		case .ExpectedRParen:
			fmt.eprintfln("Expected ')' at column %i.", col)
		case .UnexpectedToken:
			fmt.eprintfln(
				"Token '%s' unexpected at column %i.",
				scanner.tokens[parser.current].lexeme,
				col,
			)
		case .UnexpectedEOF:
			fmt.eprintln("Incomplete expression.")
		case .None:
			unreachable()
		}

		return
	}

	fmt.println(expr_to_opencl(expr))
}
