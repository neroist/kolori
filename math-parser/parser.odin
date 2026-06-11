package math_parser

import "core:mem"

Parser :: struct {
	tokens:    []Token,
	allocator: mem.Allocator,
	current:   uint,
}

// AST types.
// could we also do a union of bare structs, but instead use
// `^Expression` instead of `Expression`?
Expression :: union {
	^Real,
	^Variable,
	^Binary,
	^FunctionCall,
	^Unary,
}

Real :: struct {
	num: string,
}
Variable :: struct {
	name: string,
}
Binary :: struct {
	left:      Expression,
	right:     Expression,
	operation: BinaryType,
}
Unary :: struct {
	inner: Expression,
}
FunctionCall :: struct {
	arguments: [dynamic]Expression,
	name:      string,
}

BinaryType :: enum {
	Addition,
	Subtraction,
	Multiplication,
	Division,
	Exponentiation,
}

parse_string :: proc (source: string, functions: []string = {}, scan_flags: bit_set[Scan_Flag] = {}, allocator := context.allocator) -> (Expression, []Error_Report)
{
	tokens, errs := scan(source, functions, scan_flags, allocator)
	if len(errs) != 0 {
		return nil, errs
	}

	return parse_tokens(tokens, allocator)
}

parse_tokens :: proc (tokens: []Token, allocator := context.allocator) -> (Expression, []Error_Report)
{
	parser: Parser 
	parser_init(&parser, tokens, allocator)
	defer parser_destroy(&parser)

	expr, err := parser_parse(&parser)
	if err != nil {
		errs := make([]Error_Report, 1, allocator)
		errs[0] = err.?
		return expr, errs
	}

	return expr, {}
}

parse :: proc {
	parse_string,
	parse_tokens
}

parser_init :: proc (p: ^Parser, tokens: []Token, allocator := context.allocator)
{
	p.tokens = tokens
	p.allocator = allocator
}

parser_destroy :: proc (p: ^Parser)
{
	delete(p.tokens)
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

expression :: proc(p: ^Parser) -> (Expression, Maybe(Error_Report)) {
	return addition(p)
}

addition :: proc(p: ^Parser) -> (expr: Expression, err: Maybe(Error_Report)) {
	expr = multiplication(p) or_return
	defer if err != nil {
		expression_free(expr)
		expr = nil
	}

	for parser_match(p, {.PLUS, .MINUS}) {
		operator := parser_previous(p)
		right := multiplication(p) or_return
		bin_op := new(Binary, p.allocator)
		bin_op^ = Binary {
			operation = operator.type == .PLUS ? .Addition : .Subtraction,
			right     = right,
			left      = expr,
		}

		expr = bin_op
	}

	return expr, nil
}

multiplication :: proc(p: ^Parser) -> (expr: Expression, err: Maybe(Error_Report)) {
	expr = power(p) or_return
	defer if err != nil {
		expression_free(expr)
		expr = nil
	}

	for parser_match(p, {.ASTERISK, .SLASH}) {
		operator := parser_previous(p)
		right := power(p) or_return
		binop := new(Binary, p.allocator)
		binop^ = Binary {
			operation = operator.type == .ASTERISK ? .Multiplication : .Division,
			right     = right,
			left      = expr,
		}

		expr = binop
	}

	return expr, nil
}

power :: proc(p: ^Parser) -> (expr: Expression, err: Maybe(Error_Report)) {
	expr = unary(p) or_return
	defer if err != nil {
		expression_free(expr)
		expr = nil
	}

	for parser_match(p, {.CARET}) {
		right := unary(p) or_return
		binop := new(Binary, p.allocator)
		binop^ = Binary {
			operation = .Exponentiation,
			right     = right,
			left      = expr,
		}

		expr = binop
	}

	return expr, nil
}

unary :: proc(p: ^Parser) -> (expr: Expression, err: Maybe(Error_Report)) {
	if parser_match(p, {.MINUS}) {
		expr = new(Unary, p.allocator)
		expr.(^Unary).inner = unary(p) or_return
	} else {
		expr, err = primary(p)
		if err != nil {
			expression_free(expr)
			return nil, err
		}
	}

	return expr, nil
}

primary :: proc(p: ^Parser) -> (expr: Expression, err: Maybe(Error_Report)) {
	switch {
	case parser_match(p, {.NUMBER}):
		expr = new(Real, p.allocator)
		expr.(^Real).num = parser_previous(p).lexeme
	case parser_match(p, {.VARIABLE}):
		expr = new(Variable, p.allocator)
		expr.(^Variable).name = parser_previous(p).lexeme
	case parser_match(p, {.LEFT_PAREN}):
		opening_paren := parser_previous(p)
		expr = expression(p) or_return

		if !parser_match(p, {.RIGHT_PAREN}) {
			token := parser_previous(p)
			err = new_report(
				token,
				.ExpectedRParen,
				
				"Opening parenthesis \"(\" at location %i not closed.",
				opening_paren.column
			)
			
			expression_free(expr)
			return nil, err
		}
	case parser_match(p, {.FUNCTION}):
		expr, err = function_call(p)
	case:
		err = new_report(
			parser_previous(p),
			parser_is_at_end(p) ? .UnexpectedEOF : .UnexpectedToken
		)
	}

	return expr, err
}

function_call :: proc(p: ^Parser) -> (expr: Expression, err: Maybe(Error_Report)) {
	func_call := new(FunctionCall, p.allocator)
	func_call.name = parser_previous(p).lexeme

	if !parser_match(p, {.LEFT_PAREN}) {
		expression_free(func_call)
		token := parser_previous(p)
		err = new_report(
			token,
			.ExpectedLParen,

			"Forgot to add opening parenthesis \"(\" when calling function \"%s\".",
			token.lexeme
		)

		return nil, err
	}

	func_call.arguments, err = parameter_list(p)
	
	if !parser_match(p, {.RIGHT_PAREN}) {
		expression_free(func_call)
		token := parser_previous(p)
		err = new_report(
			token,
			.ExpectedRParen,

			"Forgot to add closing parenthesis \")\" when calling function \"%s\".",
			token.lexeme
		)

		return nil, err
	}

	return func_call, err
}

parameter_list :: proc(p: ^Parser) -> (list: [dynamic]Expression, err: Maybe(Error_Report)) {
	list = make([dynamic]Expression, p.allocator)
	defer shrink(&list)

	expr := expression(p) or_return

	append(&list, expr)

	for parser_match(p, {.COMMA}) {
		append(&list, expression(p) or_return)
	}

	return list, err
}

expression_free :: proc(expr: Expression, allocator := context.allocator) {
	context.allocator = allocator
	switch expr in expr {
	case ^Real:
		free(expr)
	case ^Variable:
		free(expr)
	case ^Binary:
		expression_free(expr.left)
		expression_free(expr.right)
		free(expr)
	case ^Unary:
		expression_free(expr.inner)
		free(expr)
	case ^FunctionCall:
		for i in expr.arguments {
			expression_free(i)
		}
		delete(expr.arguments)
		free(expr)
	}
}

parser_parse :: proc(p: ^Parser) -> (Expression, Maybe(Error_Report)) {
	assert(len(p.tokens) > 0)
	return expression(p)
}

parser_reset_state :: proc(p: ^Parser) {
	p.current = 0
}

parser_match :: proc(p: ^Parser, types: bit_set[TokenType]) -> bool {
	for type in types {
		if parser_check(p, type) {
			parser_advance(p)
			return true
		}
	}

	return false
}

parser_check :: proc(p: ^Parser, t: TokenType) -> bool {
	if parser_is_at_end(p) {
		return false
	}

	return parser_peek(p).type == t
}

// consumes the current token and return it. if we are at the end, then
// return the last token in the strean
parser_advance :: proc(p: ^Parser) -> Token {
	if !parser_is_at_end(p) {
		p.current += 1
	}

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
