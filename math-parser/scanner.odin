package math_parser

ScanError :: enum {
	None,
	UnexpectedCharacter,
}

ScanErrorReport :: struct {
	column: uint,
	error:  ScanError,
}

TokenType :: enum {
	// single-character tokens
	LEFT_PAREN,
	RIGHT_PAREN,
	CARET,
	COMMA,
	ASTERISK,
	SLASH,
	PLUS,
	MINUS,

	// literals
	VARIABLE,
	FUNCTION,
	NUMBER,
	EOF,
}

Token :: struct {
	type:   TokenType,
	lexeme: string,
	column: uint,
}

Scanner :: struct {
	tokens:    [dynamic]Token,
	errors:    [dynamic]ScanErrorReport,
	functions: []string,
	source:    string,
	start:     uint,
	current:   uint,
	// list of function names. all other identifiers are regarded as variables
}

is_digit :: proc(c: u8) -> bool {
	return (c >= '0') && (c <= '9')
}

is_alpha :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c == '_')
}

is_alphanumeric :: proc(c: u8) -> bool {
	return is_digit(c) || is_alpha(c)
}

scanner_destroy :: proc(s: ^Scanner) {
	delete(s.errors)
	delete(s.tokens)
	s.errors = nil
	s.tokens = nil
}

scanner_reset_state :: proc(s: ^Scanner) {
	s.start = 0
	s.current = 0
	resize(&s.tokens, 0)
	resize(&s.errors, 0)
}

scanner_is_function :: proc(s: ^Scanner, ident: string) -> bool {
	for func in s.functions {
		if ident == func do return true
	}

	return false
}

scanner_is_at_end :: proc(s: ^Scanner) -> bool {
	return s.current >= len(s.source)
}

scanner_advance :: proc(s: ^Scanner) -> u8 {
	if scanner_is_at_end(s) {
		return 0
	}

	char := s.source[s.current]
	s.current += 1
	return char
}

scanner_peek :: proc(s: ^Scanner) -> u8 {
	if scanner_is_at_end(s) {
		return 0
	}

	return s.source[s.current]
}

scanner_peek_next :: proc(s: ^Scanner) -> u8 {
	if s.current + 1 >= len(s.source) {
		return 0
	}

	return s.source[s.current + 1]
}

scanner_add_token :: proc(s: ^Scanner, type: TokenType) {
	append(&s.tokens, Token{type, s.source[s.start:s.current], s.current})
}

scanner_scan_number :: proc(s: ^Scanner) {
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

scanner_scan_identifier :: proc(s: ^Scanner) {
	for is_alphanumeric(scanner_peek(s)) {
		scanner_advance(s)
	}

	if scanner_is_function(s, s.source[s.start:s.current]) {
		scanner_add_token(s, .FUNCTION)
	} else {
		scanner_add_token(s, .VARIABLE)
	}
}

scanner_scan_token :: proc(s: ^Scanner) {
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
		exclude: bit_set[TokenType] = {.RIGHT_PAREN, .FUNCTION, .VARIABLE, .NUMBER}
		is_operator := len(s.tokens) == 0 || s.tokens[len(s.tokens) - 1].type in exclude
		if is_digit(scanner_peek(s)) && !is_operator {
			scanner_scan_number(s)
			break
		}

		scanner_add_token(s, .MINUS)
	case '+':
		scanner_add_token(s, .PLUS)
	case '/':
		scanner_add_token(s, .SLASH)
	case '*':
		scanner_add_token(s, .ASTERISK)
	case '^':
		scanner_add_token(s, .CARET)
	case '\t', '\n', '\v', '\f', '\r', ' ':
	case:
		if is_digit(c) {
			scanner_scan_number(s)
		} else if is_alpha(c) {
			scanner_scan_identifier(s)
		} else {
			append(&s.errors, ScanErrorReport{s.current, .UnexpectedCharacter})
		}
	}
}

scanner_insert_muls :: proc(s: ^Scanner) {
	start :: bit_set[TokenType]{.VARIABLE, .NUMBER, .RIGHT_PAREN}
	end :: bit_set[TokenType]{.VARIABLE, .FUNCTION, .LEFT_PAREN}
	for t, idx in s.tokens {
		if idx == len(s.tokens) - 1 do break

		curr := t
		next := s.tokens[idx + 1]
		if curr.type in start && next.type in end && curr.type != next.type {
			inject_at(
				&s.tokens,
				idx + 1,
				Token{type = .ASTERISK, lexeme = "*", column = (uint)(idx + 1)},
			)
		}
	}
}

scanner_scan_tokens :: proc(s: ^Scanner, implicit_multiplication := true) -> bool {
	for !scanner_is_at_end(s) {
		s.start = s.current
		scanner_scan_token(s)
	}

	append(&s.tokens, Token{.EOF, "", s.current})

	shrink(&s.errors)
	shrink(&s.tokens)

	if implicit_multiplication do scanner_insert_muls(s)

	return len(s.errors) == 0
}
