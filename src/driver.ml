open Ast
open Rename
open Eval

type backend =
    EvalBackend
  | BytecodeBackend

type driver_options = {
  filename : string;
  argv : string list;
  print_ast : bool;
  print_renamed : bool;
  backend : backend
}

exception ParseError of loc


module type EvalI = sig
  val eval : string list -> name_expr list -> value

  val eval_seq_state : eval_env -> name_expr list -> value * eval_env

  val empty_eval_env : string list -> eval_env

end

module type DriverI = sig
  val run : driver_options -> Lexing.lexbuf -> unit

  val run_eval : driver_options -> Lexing.lexbuf -> value

  val run_env : driver_options -> Lexing.lexbuf -> eval_env -> RenameScope.t -> value * eval_env * RenameScope.t
end

module rec EvalInst : EvalI = Eval.Make(struct
  let eval_require scriptPathDir modPath = 
    let driver_options = {
      filename = modPath;
      argv = [modPath];
      print_ast = false;
      print_renamed = false;
      backend = EvalBackend (* The bytecode backend does not use `Eval` anyway, so this is fine *)
    } in
    let filePath = 
      if Filename.is_relative modPath then  
        scriptPathDir ^ "/" ^ modPath
      else
        modPath
      in
    Driver.run_eval driver_options (Lexing.from_channel (In_channel.open_text filePath))
end)
and Driver : DriverI = struct

  let parse_and_rename (options : driver_options) (lexbuf : Lexing.lexbuf) (scope : RenameScope.t) : NameExpr.expr list * RenameScope.t =
    Lexing.set_filename lexbuf options.filename;
    let ast = 
      try 
        Parser.main Lexer.token lexbuf 
      with 
      | Parser.Error -> 
        let start_pos = lexbuf.lex_start_p in
        let end_pos = lexbuf.lex_curr_p in 
        raise (ParseError (Loc.from_pos start_pos end_pos)) 
    in
    if options.print_ast then begin
      print_endline "~~~~~~~~Parsed AST~~~~~~~~";
      print_endline (StringExpr.pretty_list ast);
      print_endline "~~~~~~~~~~~~~~~~~~~~~~~~~~"
    end
    else ();

    let renamed, new_scope = Rename.rename_seq_state scope ast in
    if options.print_renamed then begin
      print_endline "~~~~~~~~Renamed AST~~~~~~~";
      print_endline (NameExpr.pretty_list renamed);
      print_endline "~~~~~~~~~~~~~~~~~~~~~~~~~~"
    end
    else ();
    renamed, new_scope


  let run_env (options : driver_options) (lexbuf : Lexing.lexbuf) (env : eval_env) (scope : RenameScope.t) : value * eval_env * RenameScope.t = 
    let _ = match options.backend with
    | EvalBackend -> ()
    | BytecodeBackend -> raise (Util.Panic "The bytecode backend does not support incremental evaluation")
    in

    let renamed, new_scope = parse_and_rename options lexbuf scope in
    
    let res, new_env = EvalInst.eval_seq_state env renamed in
    res, new_env, new_scope

  let run_eval (options : driver_options) (lexbuf : Lexing.lexbuf) : value =
    let _ = match options.backend with
    | EvalBackend -> ()
    | BytecodeBackend -> raise (Util.Panic "The bytecode backend does not support value evaluation")
    in
    let res, _, _ = run_env options lexbuf (EvalInst.empty_eval_env options.argv) RenameScope.empty in
    res

  let run (options : driver_options) (lexbuf : Lexing.lexbuf) : unit =
    match options.backend with
    | EvalBackend ->   
      let _ = run_eval options lexbuf in
      ()
    | BytecodeBackend ->
      let renamed, _ = parse_and_rename options lexbuf RenameScope.empty in
      let bytecode = Compile.compile renamed in
      print_endline (Bytecode.pretty bytecode)
    
end