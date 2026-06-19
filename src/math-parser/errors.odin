package math_parser

import "core:fmt"

// ScanError :: enum {
// 	None,
// 	UnexpectedCharacter,
// }

// SyntaxError :: enum {
// 	None,
// 	ExpectedLParen,
// 	ExpectedRParen,
// 	UnexpectedToken,
// 	UnexpectedEOF,
// }

// Error :: union #shared_nil {
//     ScanError,
//     SyntaxError
// }

Error :: enum {
	// Scan errors
	None,
	UnexpectedCharacter,

	// Syntax errors
	ExpectedLParen,
	ExpectedRParen,
	UnexpectedToken,
	UnexpectedEOF,
}

Error_Report :: struct {
	using token: Token,
	msg:         string,
	error:       Error,
}

// to consolidate all default error messages in one place
@(rodata)
error_message_formats := [Error]string {
	.None                = "",
	.UnexpectedCharacter = "Unexpected character \"%s\" at position %i.",
	.ExpectedLParen      = "Expected opening parenthesis \"(\" at position %i.", // these two arent used?
	.ExpectedRParen      = "Expected closing parenthesis \")\" at position %i.",
	.UnexpectedToken     = "Unexpected token \"%s\" at position %i.",
	.UnexpectedEOF       = "Incomplete expression.",
}

new_report_default_message :: proc(token: Token, error: Error) -> Error_Report 
{
	report: Error_Report
	report.token = token
	report.error = error

	format := error_message_formats[error]
	switch error {
	case .UnexpectedCharacter, .UnexpectedToken:
		report.msg = fmt.tprintf(format, report.token.lexeme, report.column)
	case .ExpectedLParen, .ExpectedRParen:
		report.msg = fmt.tprintf(format, report.column)
	case .UnexpectedEOF:
		report.msg = fmt.tprintf(format)
	case .None:
        /* */
	}

	return report
}

new_report_custom_message :: proc(
	token: Token,
	error: Error,
	format: string,
	args: ..any,
) -> Error_Report 
{
	report: Error_Report
	report.token = token
	report.error = error
	report.msg = fmt.tprintf(format, ..args)

	return report
}

// error messages allocated using temporary allocator
new_report :: proc {
	new_report_default_message,
	new_report_custom_message,
}
