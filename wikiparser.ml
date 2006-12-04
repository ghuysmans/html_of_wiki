(* A little parser for entering valid XHTML in wikipages.
   To be extended and rewritten with ad-hoc tools (ocamllex, ocamlyacc). *)

open XHTML.M
open Ocsigen
open Ocsigen.Xhtml
open List
open String
open Str

(* TOKENS *)
let row_cmds = ["%###"; "%==="; "%---"; "%pre["; "%]"] 
let inl_cmds = ["%*"; "%/"; "%["; "%:"] (* inl_stop = "%"; esc = "\\%" *)

(* LEXER *)
let lexer row = 
  let commands = 
    (* for full_split order does matter!
       "\\%" must be the first token, as \%### is \%-###, NOT \-%###;
       "%" must be the last one, as %*abc is %*-abc, NOT %-*abc. *)
    map quote ("\\%" :: row_cmds @ inl_cmds @ ["%"]) in
  let cmd_regexp =
    regexp
      (fold_left
         (function s -> (^) (s ^ "\\|"))
         (hd commands)
         (tl commands)) 
  in map
       (function Delim d -> d | Text t -> t)
       (full_split cmd_regexp row) 

(* given [s1,s2,...,sn], returns pcdata[s1^s2^...^sn] *)
let allpcdata l = pcdata (fold_left (^) "" l) 

(* parse the argument of an inline command *)
let rec get_args = function
  | "%"::toks -> ([], toks)
  | "\\%"::toks -> let (args, rest) = get_args toks in ("%"::args, rest)
  | tok::toks when mem tok inl_cmds -> ([], tok::toks)
  | tok::toks when mem tok row_cmds -> ([], sub tok 1 ((length tok)-1) :: toks)
  | arg::toks -> let (args, rest) = get_args toks in (arg::args, rest)
  | [] -> ([], []) 

(* parse inline commands *)
let rec parse_inl_cmd a_args = function
  | "%*"::toks -> let (args, rest) = get_args toks in 
      strong[allpcdata args] :: parse_inl_cmd a_args rest
  | "%/"::toks -> let (args, rest) = get_args toks in 
      em[allpcdata args] :: parse_inl_cmd a_args rest
  | "%["::toks -> let (args, rest) = get_args toks in 
      code[allpcdata args] :: parse_inl_cmd a_args rest
  | "%:"::toks -> let (args, rest) = get_args toks in
		  let (srv,sp) = a_args in
		  let sfx = fold_left (^) "" args in 
      a srv sp [pcdata sfx] sfx :: parse_inl_cmd a_args rest
  | tok::toks -> pcdata tok :: parse_inl_cmd a_args toks
  | [] -> [] 

(* parse rows of preformatted code *)
let rec parse_code = function
  | ("%]"::_) :: rows -> ([], rows)
  | row :: rows -> let (args, rest) = parse_code rows in 
      (allpcdata(row @ ["\n"]) :: args, rest)
  | [] -> ([], [])
    
(* parse row commands *)
let rec parse_row_cmd a_args = function
  | ("%pre["::_) :: rows -> let (args, rest) = parse_code rows in 
      pre[code(args)] :: parse_row_cmd a_args rest
  | ("%###"::toks) :: rows -> h1[allpcdata toks] :: parse_row_cmd a_args rows
  | ("%==="::toks) :: rows -> h2[allpcdata toks] :: parse_row_cmd a_args rows
  | ("%---"::toks) :: rows -> h3[allpcdata toks] :: parse_row_cmd a_args rows
  | row :: rows -> p(parse_inl_cmd a_args row) :: parse_row_cmd a_args rows
  | [] -> [] 

(* LEXER+PARSER *)
let parse a_args s = 
  let rows = split (regexp "\n") s
  in parse_row_cmd a_args (map lexer rows)
