package math_parser

Parser :: struct {
	tokens:        []Token,
	current:       uint,
}

// Errors
ParseError :: enum {
	None,
	ExpectedLParen,
	ExpectedRParen,
	UnexpectedToken,
	UnexpectedEOF,
}

// AST types
Expression :: union {
	^Real,
	^Variable,
	^BinaryOperation,
	^FunctionCall,
	^Unary,
}

Real :: struct {
	num: string,
}
Variable :: struct {
	name: string,
}
BinaryOperation :: struct {
	left:      Expression,
	right:     Expression,
	operation: BinaryOperationType,
}
Unary :: struct {
	inner: Expression,
}
FunctionCall :: struct {
	arguments: [dynamic]Expression,
	name:      string,
}
BinaryOperationType :: enum {
	Addition,
	Subtraction,
	Multiplication,
	Division,
	Exponentiation,
}

/*
 * Grammar:
 * <Expression>      :: <Addition>
 * <Addition>        :: <Multiplication> {("+" | "-") <Multiplication>}
 * <Multiplication>  :: <Power> {("*" | "/") <Power>}
 * <Power>           :: <Unary> {"^" <Unary>}
 * <Unary>           :: ["-"] <Primary>
 * <Primary>         :: NUMBER | VARIABLE | "(" <Expression> ")" | <Function-Call>
 * <Function-Call>   :: FUNCTION "(" <Parameter-List> ")"
 * <Parameter-List>  :: <Expression> {"," <Expression>}
 * 
 * Note that in the definition of <Function-Call>, "<Parameter-List>" is not
 * optional. All function calls thus must have at least one argument. Consider
 * changing this in the future?
 */

expression :: proc(p: ^Parser) -> (Expression, ParseError) {
	return addition(p)
}

addition :: proc(p: ^Parser) -> (expr: Expression, err: ParseError) {
	expr = multiplication(p) or_return

	for parser_match(p, {.PLUS, .MINUS}) {
		operator := parser_previous(p)
		binop := new(BinaryOperation)
		binop^ = BinaryOperation {
			operation = operator.type == .PLUS ? .Addition : .Subtraction,
			right     = multiplication(p) or_return,
			left      = expr,
		}

		expr = binop
	}

	return expr, nil
}

multiplication :: proc(p: ^Parser) -> (expr: Expression, err: ParseError) {
	expr = power(p) or_return

	for parser_match(p, {.ASTERISK, .SLASH}) {
		operator := parser_previous(p)
		binop := new(BinaryOperation)
		binop^ = BinaryOperation {
			operation = operator.type == .ASTERISK ? .Multiplication : .Division,
			right     = power(p) or_return,
			left      = expr,
		}

		expr = binop
	}

	return expr, nil
}

power :: proc(p: ^Parser) -> (expr: Expression, err: ParseError) {
	expr = unary(p) or_return

	for parser_match(p, {.CARET}) {
		binop := new(BinaryOperation)

		binop^ = BinaryOperation {
			operation = .Exponentiation,
			right     = unary(p) or_return,
			left      = expr,
		}

		expr = binop
	}

	return expr, nil
}

unary :: proc(p: ^Parser) -> (Expression, ParseError) {
	if parser_match(p, {.MINUS}) {
		_unary := new(Unary)
		inner, err := unary(p)
		_unary^.inner = inner
		return _unary, err
	} else {
		return primary(p)
	}
}

primary :: proc(p: ^Parser) -> (expr: Expression, err: ParseError) {
	if parser_match(p, {.NUMBER}) {
		real := new(Real)
		real^.num = parser_previous(p).lexeme
		return real, nil
	} else if parser_match(p, {.VARIABLE}) {
		var := new(Variable)
		var^.name = parser_previous(p).lexeme
		return var, nil
	} else if parser_match(p, {.LEFT_PAREN}) {
		expr = expression(p) or_return
		if !parser_match(p, {.RIGHT_PAREN}) do return nil, .ExpectedRParen
		return expr, nil
	} else if parser_match(p, {.FUNCTION}) {
		return function_call(p)
	} else {
		// look at this
		return nil, parser_is_at_end(p) ? .UnexpectedEOF : .UnexpectedToken
	}
}

function_call :: proc(p: ^Parser) -> (expr: Expression, err: ParseError) {
	func_call := new(FunctionCall)
	func_call.name = parser_previous(p).lexeme

	if !parser_match(p, {.LEFT_PAREN}) do return nil, .ExpectedLParen
	func_call.arguments = parameter_list(p) or_return
	if !parser_match(p, {.RIGHT_PAREN}) do return nil, .ExpectedRParen

	return func_call, err
}

parameter_list :: proc(p: ^Parser) -> (list: [dynamic]Expression, err: ParseError) {
	exprs := make([dynamic]Expression)
	defer shrink(&exprs)

	expr := expression(p) or_return
	append(&exprs, expr)

	for parser_match(p, {.COMMA}) {
		expr = expression(p) or_return
		append(&exprs, expr)
	}

	// list = make([]Expression, len(exprs))
	// copy(list, exprs[:])

	return exprs, err
}

expression_free :: proc(expr: Expression) {
	switch expr in expr {
	case ^Real:
		free(expr)
	case ^Variable:
		free(expr)
	case ^BinaryOperation:
		expression_free(expr.left)
		expression_free(expr.right)
		free(expr)
	case ^Unary:
		expression_free(expr.inner)
	case ^FunctionCall:
		for i in expr.arguments do expression_free(i)
		delete(expr.arguments)
		free(expr)
	}
}

parser_parse :: proc(p: ^Parser) -> (Expression, ParseError) {
	return expression(p)
}

parser_reset_state :: proc(p: ^Parser) {
	p.current = 0
}

parser_match :: proc(p: ^Parser, types: []TokenType) -> bool {
	for type in types {
		if parser_check(p, type) {
			parser_advance(p)
			return true
		}
	}

	return false
}

parser_check :: proc(p: ^Parser, t: TokenType) -> bool {
	if parser_is_at_end(p) do return false
	return parser_peek(p).type == t
}

// consumes the current token and return it. if we are at the end, then
// return the last token in the strean
parser_advance :: proc(p: ^Parser) -> Token {
	if !parser_is_at_end(p) do p.current += 1
	return parser_previous(p)
}

parser_is_at_end :: proc(p: ^Parser) -> bool {
	return parser_peek(p).type == .EOF
}

parser_peek :: proc(p: ^Parser) -> Token {
	return p.tokens[p.current]
}

parser_previous :: proc(p: ^Parser) -> Token {
	return p.tokens[p.current - 1]
}
