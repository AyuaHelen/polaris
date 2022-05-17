open Polaris
open Polaris.Ast
open Polaris.Eval
open Polaris.Driver

let fatal_error (message : string) = 
  print_endline "~~~~~~~~~~~~~~ERROR~~~~~~~~~~~~~~";
  print_endline message;
  print_endline "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~";
  exit 1

let warning (message : string) =
  print_endline "~~~~~~~~~~~~~WARNING~~~~~~~~~~~~~~";
  print_endline message;
  print_endline "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"

let repl_error (message : string) = 
  print_endline ("\x1b[38;2;255;0;0mERROR\x1b[0m:\n" ^ message);

type run_options = {
  print_ast : bool;
  print_renamed : bool;
  backend : backend;
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
  | NotAValueOfType(ty, value, cxt, loc) -> print_fun (
        Loc.pretty loc ^ ": Not a value of type " ^ ty ^ "."
      ^ "\n    Context: " ^ cxt
      ^ "\n      Value: " ^ Value.pretty value
      )  
  | TryingToApplyNonFunction (value, loc) -> print_fun (
      Loc.pretty loc ^ ": Trying to apply a value that is not a function: " ^ Value.pretty value
    )
  | TryingToLookupInNonMap (value, key, loc) -> print_fun (
      Loc.pretty loc ^ ": Trying to lookup key '" ^ key ^ "' in non-map value: " ^ Value.pretty value
    )
  | MapDoesNotContain (map, key, loc) -> print_fun (
      Loc.pretty loc ^ ": Map does not contain key '" ^ key ^ "': " ^ Value.pretty (MapV map)
    )
  | InvalidNumberOfArguments (params, vals, loc) -> print_fun (
      Loc.pretty loc ^ ": Invalid number of arguments in function call.\n"
                     ^ "Expected " ^ Int.to_string (List.length params) ^ " arguments, but received " ^ Int.to_string (List.length vals) ^ ".\n"
                     ^ "    Expected: (" ^ String.concat ", " (List.map Name.original_name params) ^ ")\n"
                     ^ "      Actual: (" ^ String.concat ", " (List.map Value.pretty vals) ^ ")"
    )
  | PrimOpArgumentError (primop_name, vals, msg, loc) -> print_fun (
      Loc.pretty loc ^ ": Invalid arguments to builtin function '" ^ primop_name ^ "': " ^ msg ^ "\n"
                     ^ "    Arguments: " ^ Value.pretty (ListV vals)
    )
  | InvalidProcessArg (value, loc) -> print_fun (
      Loc.pretty loc ^ ": Argument cannot be passed to an external process in an !-Expression."
                     ^ "    Argument: " ^ Value.pretty value
    )
  | NonProgCallInPipe (expr, loc) -> print_fun (
      Loc.pretty loc ^ ": Non-program call expression found in pipe: " ^ NameExpr.pretty expr
    )

let run_file (options : run_options) (filepath : string) = 
  let _ = match options.backend with
  | EvalBackend -> ()
  | BytecodeBackend -> warning ("The bytecode backend is experimental and very incomplete. It will probably not work as expected")
  in

  let driver_options = {
    filename = filepath
  ; print_ast = options.print_ast
  ; print_renamed = options.print_renamed
  ; backend = options.backend
  } in
  handle_errors fatal_error (fun _ -> 
    Driver.run driver_options (Lexing.from_channel (open_in filepath)))

let run_repl (options : run_options) : unit =
  Sys.catch_break true;
  let _ = match options.backend with
    | EvalBackend -> ()
    | BytecodeBackend -> fatal_error "The bytecode backend does not support interactive evaluation"
  in
  let driver_options = {
      filename = "<interactive>"
    ; print_ast = options.print_ast
    ; print_renamed = options.print_renamed
    ; backend = options.backend
    } in
  let rec go env scope =
    try
      handle_errors (fun msg -> repl_error msg; go env scope)
        (fun _ -> 
          let prompt = "\x1b[1;36mλ>\x1b[0m " in
          match Readline.readline prompt with
          | None -> exit 0
          | Some input -> 
            let result, new_env, new_scope = Driver.run_env driver_options (Lexing.from_string input) env scope in

            print_endline (" - " ^ Value.pretty result);
            go new_env new_scope)
    with
    | End_of_file -> exit 0
    | Sys.Break -> 
      go env scope
  in
  go EvalInst.empty_eval_env Rename.RenameScope.empty

  

let usage_message = "usage: polaris [options] [FILE]"


let () =
  let args = ref [] in
  let anon_fun x = args := x :: !args in

  let print_ast = ref false in
  let print_renamed = ref false in
  let backend = ref "eval" in

  let speclist = [
    ("--print-ast", Arg.Set print_ast, "Print the parsed syntax tree before renaming");
    ("--print-renamed", Arg.Set print_renamed, "Print the renamed syntax tree before evaluation");
    ("--backend", Arg.Set_string backend, "The backend used for evaluation. Possible values: 'eval', 'bytecode'")
  ] in
  Arg.parse speclist anon_fun usage_message;
  
  let options = {
      print_ast = !print_ast;
      print_renamed = !print_renamed;
      backend = match !backend with
      | "eval" -> EvalBackend
      | "bytecode" -> BytecodeBackend
      | _ -> fatal_error ("Invalid or unsupported backend: '" ^ !backend ^ "'")
    } in
   match !args with
      | [filepath] -> ignore (run_file options filepath)
      | [] -> run_repl options
      | _ -> Arg.usage speclist usage_message; exit 1
