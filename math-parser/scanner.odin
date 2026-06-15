package math_parser

TokenType :: enum {
	// single-character tokens
	LEFT_PAREN,
	RIGHT_PAREN,
	CARET,
	COMMA,
	ASTERISK,
	SLASH,
	PERCENT,
	PLUS,
	MINUS,

	// literals
	VARIABLE,
	FUNCTION,
	NUMBER,

	// error
	ERROR,

	// EOF
	EOF,
}

Token :: struct {
	type:   TokenType,
	lexeme: string,
	column: uint,
}

Scanner :: struct {
	tokens:     [dynamic]Token,
	errors:     [dynamic]Error_Report,
	// list of function names. all other identifiers are regarded as variables
	functions:  []string,
	source:     string,
	scan_flags: bit_set[Scan_Flag],
	start:      uint,
	current:    uint,
}

Scan_Flag :: enum {
	Implicit_Multiplication,
}

is_digit :: proc(c: u8) -> bool 
{
	return (c >= '0') && (c <= '9')
}

is_alpha :: proc(c: u8) -> bool 
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c == '_')
}

is_alphanumeric :: proc(c: u8) -> bool 
{
	return is_digit(c) || is_alpha(c)
}

scanner_destroy :: proc(s: ^Scanner) 
{
	delete(s.errors)
	delete(s.tokens)
	s.errors = nil
	s.tokens = nil
}

scanner_reset_state :: proc(s: ^Scanner) 
{
	s.start = 0
	s.current = 0
	resize(&s.tokens, 0)
	resize(&s.errors, 0)
}

scanner_is_function :: proc(s: ^Scanner, ident: string) -> bool 
{
	for func in s.functions {
		if ident == func {
			return true
		}
	}

	return false
}

scanner_is_at_end :: proc(s: ^Scanner) -> bool 
{
	return s.current >= len(s.source)
}

scanner_advance :: proc(s: ^Scanner) -> u8 
{
	if scanner_is_at_end(s) {
		return 0
	}

	char := s.source[s.current]
	s.current += 1
	return char
}

scanner_peek :: proc(s: ^Scanner) -> u8 
{
	if scanner_is_at_end(s) {
		return 0
	}

	return s.source[s.current]
}

scanner_peek_next :: proc(s: ^Scanner) -> u8 
{
	if s.current + 1 >= len(s.source) {
		return 0
	}

	return s.source[s.current + 1]
}

scanner_add_token :: proc(s: ^Scanner, type: TokenType) 
{
	append(&s.tokens, Token{type, s.source[s.start:s.current], s.current})
}

scanner_scan_number :: proc(s: ^Scanner) 
{
	for is_digit(scanner_peek(s)) {
		scanner_advance(s)
	}

	if scanner_peek(s) == '.' && is_digit(scanner_peek_next(s)) {
		scanner_advance(s)

		for is_digit(scanner_peek(s)) {
			scanner_advance(s)
		}
	}

	scanner_add_token(s, .NUMBER)
}

scanner_scan_identifier :: proc(s: ^Scanner) 
{
	for is_alphanumeric(scanner_peek(s)) {
		scanner_advance(s)
	}

	if scanner_is_function(s, s.source[s.start:s.current]) {
		scanner_add_token(s, .FUNCTION)
	} else {
		scanner_add_token(s, .VARIABLE)
	}
}

scanner_scan_token :: proc(s: ^Scanner) 
{
	c := scanner_advance(s)
	switch c {
	case '(':
		scanner_add_token(s, .LEFT_PAREN)
	case ')':
		scanner_add_token(s, .RIGHT_PAREN)
	case ',':
		scanner_add_token(s, .COMMA)
	case '-':
		// allow negative numbers as number literals
		// when: when we see a minus sign, we probably have a negative
		//       number when the next character is a digit and the 
		//       preceeding tokens do not imply that it may be used as
		//       an operator instead
		exclude: bit_set[TokenType] = {
			.RIGHT_PAREN,
			.FUNCTION,
			.VARIABLE,
			.NUMBER,
		}
		is_operator :=
			len(s.tokens) == 0 || s.tokens[len(s.tokens) - 1].type in exclude
		if is_digit(scanner_peek(s)) && !is_operator {
			scanner_scan_number(s)
			break
		}

		scanner_add_token(s, .MINUS)
	case '+':
		scanner_add_token(s, .PLUS)
	case '%':
		scanner_add_token(s, .PERCENT)
	case '/':
		scanner_add_token(s, .SLASH)
	case '*':
		scanner_add_token(s, .ASTERISK)
	case '^':
		scanner_add_token(s, .CARET)
	case '\t', '\n', '\v', '\f', '\r', ' ':
	/* */
	case:
		if is_digit(c) {
			scanner_scan_number(s)
		} else if is_alpha(c) {
			scanner_scan_identifier(s)
		} else {
			scanner_add_token(s, .ERROR)
			append(
				&s.errors,
				new_report(s.tokens[len(s.tokens) - 1], .UnexpectedCharacter),
			)
		}
	}
}

scanner_insert_muls :: proc(s: ^Scanner) 
{
	start :: bit_set[TokenType]{.VARIABLE, .NUMBER, .RIGHT_PAREN}
	end :: bit_set[TokenType]{.VARIABLE, .FUNCTION, .LEFT_PAREN}
	for t, idx in s.tokens {
		if idx == len(s.tokens) - 1 {
			break
		}

		curr := t
		next := s.tokens[idx + 1]
		if curr.type in start && next.type in end && curr.type != next.type {
			inject_at(
				&s.tokens,
				idx + 1,
				Token {
					type = .ASTERISK,
					lexeme = "*",
					column = (uint)(idx + 1),
				},
			)
		}
	}
}

scanner_scan_tokens :: proc(s: ^Scanner) -> (ok: bool) 
{
	for !scanner_is_at_end(s) {
		s.start = s.current
		scanner_scan_token(s)
	}

	append(&s.tokens, Token{.EOF, "", s.current})

	shrink(&s.errors)
	shrink(&s.tokens)

	if .Implicit_Multiplication in s.scan_flags {
		scanner_insert_muls(s)
	}

	ok = len(s.errors) == 0
	return ok
}

scanner_init :: proc(
	s: ^Scanner,
	source: string,
	functions: []string = {},
	scan_flags: bit_set[Scan_Flag] = {},
	allocator := context.allocator,
) 
{
	s.tokens = make([dynamic]Token, allocator)
	s.errors = make([dynamic]Error_Report, allocator)
	s.functions = functions
	s.source = source
	s.scan_flags = scan_flags
}

scan :: proc(
	source: string,
	functions: []string = {},
	scan_flags: bit_set[Scan_Flag] = {},
	allocator := context.allocator,
) -> (
	[]Token,
	[]Error_Report,
) 
{
	scanner: Scanner
	scanner_init(&scanner, source, functions, scan_flags, allocator)
	scanner_scan_tokens(&scanner)

	return scanner.tokens[:], scanner.errors[:]
}
