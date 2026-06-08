#+build ignore
#+private(file)

package math_parser

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

eval :: proc(expr: Expression) -> f64 {
	switch expr in expr {
	case ^Real:
		num, _ := strconv.parse_f64(expr.num)
		return num
	case ^Variable:
		switch expr.name {
		case "e":
			return math.E
		case "pi":
			return math.PI
		case "tau":
			return math.TAU
		}
	case ^BinaryOperation:
		switch expr.operation {
		case .Addition:
			return eval(expr.left) + eval(expr.right)
		case .Subtraction:
			return eval(expr.left) - eval(expr.right)
		case .Multiplication:
			return eval(expr.left) * eval(expr.right)
		case .Division:
			return eval(expr.left) / eval(expr.right)
		case .Exponentiation:
			return math.pow(eval(expr.left), eval(expr.right))
		}
	case ^FunctionCall:
		switch expr.name {
		case "sin":
			return math.sin(eval(expr.arguments[0]))
		case "cos":
			return math.cos(eval(expr.arguments[0]))
		case "tan":
			return math.tan(eval(expr.arguments[0]))
		case "csc":
			return math.pow(math.sin(eval(expr.arguments[0])), -1)
		case "sec":
			return math.pow(math.cos(eval(expr.arguments[0])), -1)
		case "cot":
			return math.pow(math.tan(eval(expr.arguments[0])), -1)
		case "asin":
			return math.asin(eval(expr.arguments[0]))
		case "acos":
			return math.acos(eval(expr.arguments[0]))
		case "atan":
			return math.atan(eval(expr.arguments[0]))
		case "exp":
			return math.exp(eval(expr.arguments[0]))
		case "ln":
			return math.ln(eval(expr.arguments[0]))
		case "sqrt":
			return math.sqrt(eval(expr.arguments[0]))
		case "cbrt":
			return math.pow(eval(expr.arguments[0]), 1 / 3)
		}
	case ^Unary:
		return -eval(expr.inner)
	}

	return 0
}

expr_to_str :: proc(expr: Expression) -> string {
	switch expr in expr {
	case ^Real:
		return expr.num
	case ^Variable:
		return expr.name
	case ^BinaryOperation:
		ops := [BinaryOperationType]u8 {
			.Addition       = '+',
			.Subtraction    = '-',
			.Multiplication = '*',
			.Division       = '/',
			.Exponentiation = '^',
		}

		return fmt.tprintf(
			"(%s %c %s)",
			expr_to_str(expr.left),
			ops[expr.operation],
			expr_to_str(expr.right),
		)
	case ^FunctionCall:
		builder := new(strings.Builder)
		strings.builder_init(builder)
		defer free(builder)

		fmt.sbprint(builder, expr.name)
		fmt.sbprint(builder, "(")

		fmt.sbprint(builder, expr_to_str(expr.arguments[0]))
		for i in expr.arguments[1:] {
			fmt.sbprint(builder, ",", expr_to_str(i))
		}
		
		fmt.sbprint(builder, ")")

		return strings.to_string(builder^)
	case ^Unary:
		return fmt.tprintf("-%s", expr_to_str(expr.inner))
	case:
		return ""
	}
}

main :: proc() {
	scanner := new(Scanner)
	scanner.source = "e^("
	scanner.functions = {"sin", "cos", "tan"}
	defer scanner_destroy(scanner)
	defer free(scanner)

	parser := new(Parser)
	parser.tokens = scanner.tokens[:]
	defer free(parser)

	scanner_scan_tokens(scanner)
	expr, err := expression(parser)
	defer expression_free(expr)

	if err == .None {
		fmt.println(scanner.source)
		fmt.println(expr_to_str(expr))
		fmt.println(eval(expr))
	} else {
		fmt.println(err)
		// fmt.println(scanner.tokens[parser.current])
	}
}
