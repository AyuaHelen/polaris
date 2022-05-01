open Polaris
open Polaris.Ast
open Polaris.Eval
open Polaris.Driver

let fatal_error (message : string) = 
  print_endline "~~~~~~~~~~~~~~ERROR~~~~~~~~~~~~~~";
  print_endline message;
  print_endline "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~";
  exit 1

let repl_error (message : string) = 
  print_endline ("\x1b[38;2;128;3;4mERROR\x1b[0m:\n" ^ message);

type run_options = {
  print_ast : bool;
  print_renamed : bool
}

let handle_errors print_fun f = 
  let open Rename.RenameError in 
  let open Eval.EvalError in
  try 
    f ()
  with 
  | ParseError loc -> print_fun ("Parse Error at " ^ Loc.pretty loc)
  | Sys_error msg -> print_fun ("System error: " ^ msg)
  (* RenameError *)
  | VarNotFound (x, loc) -> print_fun (Loc.pretty loc ^ ": Variable not found: '" ^ x ^ "'")
  | LetSeqInNonSeq (expr, loc) -> print_fun (
        Loc.pretty loc ^ ": Let expression without 'in' found outside a sequence expression.\n"
      ^ "    Expression: " ^ StringExpr.pretty expr
      )
  (* EvalError *)
  | DynamicVarNotFound (x, loc) -> print_fun (
        Loc.pretty loc ^ ": Variable not found during execution: '" ^ Name.pretty x ^ "'\n"
      ^ "This is definitely a bug in the interpreter"
      )

let run_file (options : run_options) (filepath : string) : value = 
  let driver_options = {
    filename = filepath
  ; print_ast = options.print_ast
  ; print_renamed = options.print_renamed
  } in
  handle_errors fatal_error (fun _ -> 
    Driver.run driver_options (Lexing.from_channel (open_in filepath)))

let run_repl (options : run_options) : unit =
  let driver_options = {
      filename = "<interactive>"
    ; print_ast = options.print_ast
    ; print_renamed = options.print_renamed
    } in
    let rec go env scope =
      handle_errors (fun msg -> repl_error msg; go env scope)
        (fun _ ->  
          print_string "λ> ";
          flush stdout;
          let input = read_line () in

          let result, new_env, new_scope = Driver.run_env driver_options (Lexing.from_string input) env scope in
          
          print_endline (" - " ^ Value.pretty result);
          go new_env new_scope)
    in
    go empty_eval_env Rename.RenameScope.empty

  

let usage_message = "usage: polaris [options] [FILE]"


let () =
  let args = ref [] in
  let anon_fun x = args := x :: !args in

  let print_ast = ref false in
  let print_renamed = ref false in


  let speclist = [
    ("--print-ast", Arg.Set print_ast, "Print the parsed syntax tree before renaming");
    ("--print-renamed", Arg.Set print_renamed, "Print the renamed syntax tree before evaluation")
  ] in
  Arg.parse speclist anon_fun usage_message;
  
  let options = {
      print_ast = !print_ast;
      print_renamed = !print_renamed
    } in
  match !args with
    | [filepath] -> ignore (run_file options filepath)
    | [] -> run_repl options
    | _ -> Arg.usage speclist usage_message; exit 1