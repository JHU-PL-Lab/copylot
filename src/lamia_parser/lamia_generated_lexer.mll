{
  open Lamia_generated_parser;;
}

let digit = ['0'-'9']
let integer = '-'? digit+

let identifier_start = ['a'-'z' 'A'-'Z' '_' '$']
let identifier_cont = identifier_start | ['0'-'9']
let identifier = identifier_start identifier_cont*

let memory_identifier = '&' identifier

let notquote = [^'"'] | ('"' '\\')
let stringpart = notquote
let string_literal = '"' stringpart* '"'

rule token = parse
  | [' ' '\n' '\t'] { token lexbuf }

  | ";;" { DOUBLE_SEMICOLON }

  | ';' { SEMICOLON }
  | ':' { COLON }
  | "==" { ISEQUAL }
  | "||" { LISTCONCAT }
  | '=' { EQUAL }
  | '(' { OPEN_PAREN }
  | ')' { CLOSE_PAREN }
  | '{' { OPEN_BRACE }
  | '}' { CLOSE_BRACE }
  | '[' { OPEN_BRACKET }
  | ']' { CLOSE_BRACKET }
  | "->" { ARROW }
  | ',' { COMMA }
  | '@' { AT }

  | "let" { LET }
  | "alloc" { ALLOC }
  | "store" { STORE }
  | "get" { GET }
  | "is" { IS }
  | "return" { RETURN }
  | "ifresult" { IFRESULT }
  | "raise" { RAISE }
  | "try" { TRY }
  | "except" { EXCEPT }
  | "if" { IF }
  | "then" { THEN }
  | "else" { ELSE }
  | "while" { WHILE }
  | "True" { BOOL(true) }
  | "False" { BOOL(false) }
  | "def" { DEF }
  | "None" { NONE }

  | "not" { NOT }
  | "haskey" { HASKEY }
  | "isint" {ISINT}
  | "isfunc" {ISFUNC}

  | "int+" { INTPLUS }
  | "int-" { INTMINUS }

  | identifier as x { IDENT(x) }
  | memory_identifier as y { MEMIDENT(y) }
  | integer as n { INTEGER(int_of_string n) }
  | string_literal as s { STRING(String.sub s 1 (String.length s - 2)) }
  | eof { EOF }
