#+build ignore
#+private(file)

package math_parser

import "core:strings"
import "core:strconv"
import "core:math"
import "core:mem"
import "core:fmt"

@(rodata)
ops := [BinaryType]u8 {
	.Addition       = '+',
	.Subtraction    = '-',
	.Multiplication = '*',
	.Division       = '/',
	.Exponentiation = '^',
}

eval :: proc(expr: Expression) -> f64 {
	switch expr in expr {
	case ^Real:
		num := strconv.parse_f64(expr.num) or_else unreachable()
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
	case ^Binary:
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
			return math.tan((math.PI/2) - eval(expr.arguments[0]))
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
	case ^Binary:
		return fmt.tprintf(
			"(%s %c %s)",
			expr_to_str(expr.left),
			ops[expr.operation],
			expr_to_str(expr.right),
		)
	case ^FunctionCall:
		builder: strings.Builder
		strings.builder_init(&builder, context.temp_allocator)

		fmt.sbprint(&builder, expr.name)
		fmt.sbprintf(&builder, "(")

		fmt.sbprint(&builder, expr_to_str(expr.arguments[0]))
		for i in expr.arguments[1:] {
			fmt.sbprint(&builder, ",", expr_to_str(i))
		}
		
		fmt.sbprint(&builder, ")")

		return strings.to_string(builder)
	case ^Unary:
		return fmt.tprintf("-%s", expr_to_str(expr.inner))
	case:
		return ""
	}
}

main :: proc() {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)

	defer {
		if len(track.allocation_map) > 0 {
			fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
			for _, entry in track.allocation_map {
				fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
			}
		}
		mem.tracking_allocator_destroy(&track)
	}

	scanner := new(Scanner)
	scanner.source = "x^(y+1"
	scanner.functions = {"sin", "cos", "tan"}
	defer free(scanner)
	defer scanner_destroy(scanner)
	
	parser := new(Parser)
	scanner_scan_tokens(scanner)
	parser.tokens = scanner.tokens[:]
	parser.allocator = context.allocator
	
	defer free(parser)

	expr, err := parser_parse(parser)
	defer expression_free(expr)

	if err == nil {
		fmt.println(scanner.source)
		fmt.println(expr_to_str(expr))
		fmt.println(eval(expr))
	} else {
		fmt.println(err)
		// fmt.println(scanner.tokens[parser.current])
	}
}
