package tests

import math_parser ".."
import "core:fmt"
import "core:log"
import "core:math"
import "core:strconv"
import "core:strings"
import "core:testing"

eval :: proc(expr: math_parser.Expression) -> f64 
{
	switch expr in expr {
	case ^math_parser.Real:
		num, _ := strconv.parse_f64(expr.num)
		return num
	case ^math_parser.Variable:
		switch expr.name {
		case "e":
			return math.E
		case "pi":
			return math.PI
		case "tau":
			return math.TAU
		}
	case ^math_parser.Binary:
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
	case ^math_parser.FunctionCall:
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
	case ^math_parser.Unary:
		return -eval(expr.inner)
	}

	return 0
}

expr_to_str :: proc(expr: math_parser.Expression) -> string 
{
	switch expr in expr {
	case ^math_parser.Real:
		return expr.num
	case ^math_parser.Variable:
		return expr.name
	case ^math_parser.Binary:
		ops := [math_parser.BinaryType]u8 {
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
	case ^math_parser.FunctionCall:
		builder := new(strings.Builder)
		strings.builder_init(builder)
		defer strings.builder_destroy(builder)
		defer free(builder)

		fmt.sbprint(builder, expr.name)
		fmt.sbprint(builder, "(")
		fmt.sbprint(builder, expr_to_str(expr.arguments[0]))
		for i in expr.arguments[1:] {
			fmt.sbprint(builder, ",", expr_to_str(i))
		}
		fmt.sbprint(builder, ")")

		return strings.to_string(builder^)
	case ^math_parser.Unary:
		return fmt.tprintf("-%s", expr_to_str(expr.inner))
	}

	return ""
}

@(test)
prescendence :: proc(t: ^testing.T) 
{
	EXPRSTR :: "1 + 2 * 3 ^ 4"

	expr, _ := math_parser.parse(EXPRSTR)
	defer math_parser.expression_free(expr)

	evaluation := eval(expr)
	ACTUAL_ANSWER :: 163

	log.info("Input:\t", EXPRSTR)
	log.info("Interpretation:\t", expr_to_str(expr))
	log.info("Evaluated", EXPRSTR, "-- got", evaluation)
	testing.expect(
		t,
		evaluation == ACTUAL_ANSWER,
		fmt.tprintf(EXPRSTR, "failed to equal", ACTUAL_ANSWER),
	)
}

@(test)
parentheses :: proc(t: ^testing.T) 
{
	EXPRSTR :: "(((10*(100)*((((20+4)*(2*2*9+3-3)))))/100)^2)^2"

	expr, _ := math_parser.parse(EXPRSTR)
	defer math_parser.expression_free(expr)

	evaluation := eval(expr)
	ACTUAL_ANSWER :: 5572562780160000

	log.info("Input:\t", EXPRSTR)
	log.info("Interpretation:\t", expr_to_str(expr))
	log.info("Evaluated", EXPRSTR, "-- got", evaluation)
	testing.expect(
		t,
		evaluation == ACTUAL_ANSWER,
		fmt.tprint(EXPRSTR, "failed to equal", ACTUAL_ANSWER),
	)
}

@(test)
functions :: proc(t: ^testing.T) 
{
	EXPRSTR :: "exp(2) * exp(ln(e) - 3) + cos(pi/4) * sin(pi/4)"

	expr, _ := math_parser.parse(EXPRSTR, []string{"exp", "ln", "sin", "cos"})
	defer math_parser.expression_free(expr)

	evaluation := eval(expr)
	ACTUAL_ANSWER :: 1.5

	log.info("Input:\t", EXPRSTR)
	log.info("Interpretation:\t", expr_to_str(expr))
	log.info("Evaluated", EXPRSTR, "-- got", evaluation)
	testing.expect(
		t,
		evaluation == ACTUAL_ANSWER,
		fmt.tprint(EXPRSTR, "failed to equal", ACTUAL_ANSWER),
	)
}

@(test)
errors :: proc(t: ^testing.T) 
{
	EXPRSTR :: "exp(2) * exp(ln(e) - 3) + cos(pi/4) * sin(pi/4)"

	expr, _ := math_parser.parse(EXPRSTR, []string{"exp", "ln", "sin", "cos"})
	defer math_parser.expression_free(expr)

	evaluation := eval(expr)
	ACTUAL_ANSWER :: 1.5

	log.info("Input:\t", EXPRSTR)
	log.info("Interpretation:\t", expr_to_str(expr))
	log.info("Evaluated", EXPRSTR, "-- got", evaluation)
	testing.expect(
		t,
		evaluation == ACTUAL_ANSWER,
		fmt.tprint(EXPRSTR, "failed to equal", ACTUAL_ANSWER),
	)
}
