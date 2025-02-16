(**********************************************************************)
(* Equations                                                          *)
(* Copyright (c) 2009-2020 Matthieu Sozeau <matthieu.sozeau@inria.fr> *)
(**********************************************************************)
(* This file is distributed under the terms of the                    *)
(* GNU Lesser General Public License Version 2.1                      *)
(**********************************************************************)

open Printer
open Ppconstr
open Util
open Names
open Constr
open Pp
open Glob_term
open List
open Libnames
open Constrexpr_ops
open Constrexpr
open Evar_kinds
open Equations_common
open Constrintern

type 'a with_loc = Loc.t * 'a
type identifier = Names.Id.t
   
type generated = bool

(** User-level patterns *)
type user_pat =
    PUVar of identifier * generated
  | PUCstr of constructor * int * user_pats
  | PUInac of Glob_term.glob_constr
  | PUEmpty
and user_pat_loc = (user_pat, [ `any ]) DAst.t
and user_pats = user_pat_loc list

(** AST *)

type pat_expr =
  | PEApp of qualid Constrexpr.or_by_notation with_loc * pat_expr with_loc list
  | PEWildcard
  | PEInac of constr_expr

type user_pat_expr = pat_expr with_loc

type 'a input_pats =
  | SignPats of 'a
  | RefinePats of 'a list

type rec_annotation =
  | Nested
  | Mutual

type user_rec_annot = rec_annotation option

type rec_arg = int * Id.t with_loc option
    
type rec_annot =
  | MutualOn of rec_arg option
  | NestedOn of rec_arg option
  | NestedNonRec

type program_body =
  | ConstrExpr of Constrexpr.constr_expr
  | GlobConstr of Glob_term.glob_constr
  | Constr of EConstr.constr (* We interpret a constr by substituting
                                [Var names] of the lhs bound variables
                                with the proper de Bruijn indices *)

type lhs = user_pats

and ('a,'b) rhs_aux =
    Program of program_body * 'a wheres
  | Empty of identifier with_loc
  | Refine of Constrexpr.constr_expr list * 'b list

and ('a,'b) rhs = ('a, 'b) rhs_aux option (* Empty patterns allow empty r.h.s. *)

and pre_prototype =
  identifier with_loc * user_rec_annot * Constrexpr.local_binder_expr list * Constrexpr.constr_expr option *
  (Id.t with_loc option, Constrexpr.constr_expr * Constrexpr.constr_expr option) by_annot option

and ('a, 'b) by_annot =
  | Structural of 'a
  | WellFounded of 'b

and 'a where_clause = pre_prototype * 'a list
and 'a wheres = 'a where_clause list * Vernacexpr.decl_notation list

type program = (signature * clause list) list
and signature = identifier * rel_context * constr (* f : Π Δ. τ *)
and clause = Loc.t option * lhs * (clause, clause) rhs (* lhs rhs *)

type pre_equation = Constrexpr.constr_expr input_pats * (pre_equation, pre_equation) rhs

type pre_clause = Loc.t option * lhs * (pre_equation, pre_clause) rhs

type pre_equations = pre_equation where_clause list

let rec pr_user_loc_pat env sigma ?loc pat =
  match pat with
  | PUVar (i, gen) -> Id.print i ++ if gen then str "#" else mt ()
  | PUCstr (c, i, f) -> 
      let pc = pr_constructor env c in
        if not (List.is_empty f) then str "(" ++ pc ++ spc () ++ pr_user_pats env sigma f ++ str ")"
	else pc
  | PUInac c -> str "?(" ++ pr_glob_constr_env env sigma c ++ str ")"
  | PUEmpty -> str"!"

and pr_user_pat env sigma = DAst.with_loc_val (pr_user_loc_pat env sigma)

and pr_user_pats env sigma pats =
  prlist_with_sep spc (pr_user_pat env sigma) pats

let pr_lhs = pr_user_pats

let pplhs lhs =
  let env = Global.env () in
  let sigma = Evd.from_env env in
  pp (pr_lhs env sigma lhs)

let pr_body env sigma = function
  | ConstrExpr rhs -> pr_constr_expr env sigma rhs
  | GlobConstr rhs -> pr_glob_constr_env env sigma rhs
  | Constr c -> str"<constr>"

let rec pr_rhs_aux env sigma = function
  | Empty (loc, var) -> spc () ++ str ":=!" ++ spc () ++ Id.print var
  | Program (rhs, where) -> spc () ++ str ":=" ++ spc () ++ pr_body env sigma rhs ++
                            spc () ++ pr_wheres env sigma where
  | Refine (rhs, s) -> spc () ++ str "with" ++ spc () ++
                       prlist_with_sep (fun () -> str",") (pr_constr_expr env sigma) rhs ++
      spc () ++ str "=>" ++ spc () ++
      hov 1 (str "{" ++ pr_clauses env sigma s ++ str "}")

and pr_rhs env sigma = function
  | None -> mt ()
  | Some rhs -> pr_rhs_aux env sigma rhs
and pr_wheres env sigma (l, nts) =
  if List.is_empty l then mt() else
  str"where" ++ spc () ++ prlist_with_sep fnl (pr_where env sigma) l
and pr_where env sigma (sign, eqns) =
  pr_proto env sigma sign ++ str "{" ++ pr_clauses env sigma eqns ++ str "}"
and pr_proto env sigma ((_,id), _, l, t, ann) =
  Id.print id ++ pr_binders env sigma l ++ pr_opt (fun t -> str" : " ++ pr_constr_expr env sigma t) t ++
  (match ann with
     None -> mt ()
   | Some (WellFounded (t, rel)) -> str"by wf " ++ pr_constr_expr env sigma t ++ pr_opt (pr_constr_expr env sigma) rel
   | Some (Structural id) -> str"by struct " ++ pr_opt (fun x -> pr_id (snd x)) id)

and pr_clause env sigma (loc, lhs, rhs) =
  pr_lhs env sigma lhs ++ pr_rhs env sigma rhs

and pr_clauses env sigma =
  prlist_with_sep fnl (pr_clause env sigma)

let pr_user_lhs env sigma lhs =
  match lhs with
  | SignPats x -> pr_constr_expr env sigma x
  | RefinePats l -> prlist_with_sep (fun () -> str "|") (pr_constr_expr env sigma) l

let rec pr_user_rhs_aux env sigma = function
  | Empty (loc, var) -> spc () ++ str ":=!" ++ spc () ++ Id.print var
  | Program (rhs, where) -> spc () ++ str ":=" ++ spc () ++
                            pr_body env sigma rhs ++
                            spc () ++ pr_prewheres env sigma where
  | Refine (rhs, s) -> spc () ++ str "with" ++ spc () ++
                       prlist_with_sep (fun () -> str ",") (pr_constr_expr env sigma) rhs ++
      spc () ++ str "=>" ++ spc () ++
      hov 1 (str "{" ++ pr_user_clauses env sigma s ++ str "}")

and pr_prerhs_aux env sigma = function
  | Empty (loc, var) -> spc () ++ str ":=!" ++ spc () ++ Id.print var
  | Program (rhs, where) -> spc () ++ str ":=" ++ spc () ++
                            pr_body env sigma rhs ++
                            spc () ++ pr_prewheres env sigma where
  | Refine (rhs, s) -> spc () ++ str "with" ++ spc () ++
                       prlist_with_sep (fun () -> str ",") (pr_constr_expr env sigma) rhs ++
      spc () ++ str "=>" ++ spc () ++
      hov 1 (str "{" ++ pr_preclauses env sigma s ++ str "}")

and pr_user_rhs env sigma = pr_opt (pr_user_rhs_aux env sigma)
and pr_prerhs env sigma = pr_opt (pr_prerhs_aux env sigma)

and pr_user_clause env sigma (lhs, rhs) =
  pr_user_lhs env sigma lhs ++ pr_user_rhs env sigma rhs

and pr_user_clauses env sigma =
  prlist_with_sep fnl (pr_user_clause env sigma)

and pr_prewheres env sigma (l, nts) =
  if List.is_empty l then mt() else
  str"where" ++ spc () ++ prlist_with_sep fnl (pr_prewhere env sigma) l
and pr_prewhere env sigma (sign, eqns) =
  pr_proto env sigma sign ++ str "{" ++ pr_user_clauses env sigma eqns ++ str "}"

and pr_preclause env sigma (loc, lhs, rhs) =
  pr_lhs env sigma lhs ++ pr_prerhs env sigma rhs

and pr_preclauses env sigma =
  prlist_with_sep fnl (pr_preclause env sigma)

let ppclause clause =
  let env = Global.env () in
  let sigma = Evd.from_env env in
  pp(pr_clause env sigma clause)

let wit_equations_list : pre_equation list Genarg.uniform_genarg_type =
  Genarg.create_arg "equations_list"

let next_ident_away s ids =
  let n' = Namegen.next_ident_away s !ids in
    ids := Id.Set.add n' !ids; n'

type equation_option = OInd | OEquations
    
type equation_user_option = equation_option * bool

type equation_options = equation_user_option list

let pr_r_equation_user_option _prc _prlc _prt l =
  mt ()

let pr_equation_options  _prc _prlc _prt l =
  mt ()

type rec_type_item =
  | Guarded of (Id.t * rec_annot) list (* for mutual rec *)
  | Logical of Id.t with_loc (* for nested wf rec *)

type rec_type = rec_type_item option list

let is_structural = function Some (Guarded _) :: _ -> true | _ -> false

let has_logical rec_type =
  List.exists (function Some (Logical _) -> true | _ -> false) rec_type

let is_rec_call sigma id f =
  match EConstr.kind sigma f with
  | Var id' -> Id.equal id id'
  | Const (c, _) ->
    let id' = Label.to_id (Constant.label c) in
    Id.equal id id'
  | _ -> false

let default_loc = Loc.make_loc (0, 0)
         
let free_vars_of_constr_expr fid c =
  let rec aux bdvars l = function
    | { CAst.v = CRef (qid, _) } when qualid_is_ident qid ->
      let id = qualid_basename qid in
      if Id.List.mem id bdvars then l
      else if Option.cata (Id.equal id) false fid then l
      else
        (try
           match Nametab.locate_extended (Libnames.qualid_of_ident id) with
           | Globnames.TrueGlobal gr ->
             if not (Globnames.isConstructRef gr) then Id.Set.add id l
             else l
           | Globnames.SynDef _ -> l
         with Not_found -> Id.Set.add id l)
    | { CAst.v = CNotation (_,(InConstrEntry, "?( _ )"), _) } -> l
    | c -> fold_constr_expr_with_binders (fun a l -> a::l) aux bdvars l c
  in aux [] Id.Set.empty c

let ids_of_pats id pats =
  fold_left (fun ids p -> Id.Set.union ids (free_vars_of_constr_expr id p))
    Id.Set.empty pats

type wf_rec_info =
  Constrexpr.constr_expr * Constrexpr.constr_expr option * Id.t with_loc

type program_rec_info =
  (rec_annot, wf_rec_info) by_annot

type program_info = {
  program_loc : Loc.t;
  program_id : Id.t;
  program_orig_type : EConstr.t; (* The original type *)
  program_sort : Univ.Universe.t; (* The sort of this type *)
  program_sign : EConstr.rel_context;
  program_arity : EConstr.t;
  program_rec : program_rec_info option;
  program_impls : Impargs.manual_implicits;
  program_implicits : Impargs.implicit_status list;
}

let map_universe f u =
  let u' = f (EConstr.mkSort (Sorts.sort_of_univ u)) in
  match Constr.kind (EConstr.Unsafe.to_constr u') with
  | Sort s -> Sorts.univ_of_sort s
  | _ -> assert false

let map_program_info f p =
  { p with
    program_orig_type = f p.program_orig_type;
    program_sort = map_universe f p.program_sort;
    program_sign = map_rel_context f p.program_sign;
    program_arity = f p.program_arity }

let _chole c loc =
  (* let tac = Genarg.in_gen (Genarg.rawwit Constrarg.wit_tactic) (solve_rec_tac_expr ()) in *)
  let kn = Lib.make_kn c in
  let cst = Names.Constant.make kn kn in
  CAst.make ~loc
  (CHole (Some (ImplicitArg (GlobRef.ConstRef cst, (0,None), false)), Namegen.IntroAnonymous,None)), None

let _check_linearity env sigma opats =
  let rec aux ids pats = 
    List.fold_left (fun ids pat ->
      DAst.with_loc_val (fun ?loc pat ->
      match pat with
      | PUVar (n, _) ->
	if Id.Set.mem n ids then
	  CErrors.user_err ?loc ~hdr:"ids_of_pats"
            (str "Non-linear occurrence of variable in patterns: " ++ pr_user_pats env sigma opats)
	else Id.Set.add n ids
      | PUInac _ -> ids
      | PUEmpty -> ids
      | PUCstr (_, _, pats) -> aux ids pats) pat)
      ids pats
  in ignore (aux Id.Set.empty opats)

let pattern_of_glob_constr env sigma avoid patname gc =
  let rec constructor ?loc c l =
    let ind, _ = c in
    let nparams = Inductiveops.inductive_nparams env ind in
    let nargs = Inductiveops.constructor_nrealargs env c in
    let l =
      if List.length l < nargs then
        user_err_loc (loc, "pattern_of_glob_constr", str "Constructor is applied to too few arguments")
      else
        if List.length l = nparams + nargs then
          List.skipn nparams l
        else if List.length l = nargs then l
        else
          user_err_loc (loc, "pattern_of_glob_constr", str "Constructor is applied to too many arguments");
    in
    Dumpglob.add_glob ?loc (GlobRef.ConstructRef c);
    PUCstr (c, nparams, List.map (DAst.map_with_loc aux) l)
  and aux ?loc = function
    | GVar id -> PUVar (id, false)
    | GHole (_,_,_) ->
      let id =
        match patname with
        | Anonymous -> Id.of_string "wildcard"
        | Name id -> id
      in
      let n = next_ident_away id avoid in
      PUVar (n, true)
    | GRef (GlobRef.ConstructRef cstr,_) -> constructor ?loc cstr []
    | GRef (GlobRef.ConstRef _ as c, _) when GlobRef.equal c (Lazy.force coq_bang) -> PUEmpty
    | GApp (c, l) ->
      begin match DAst.get c with
        | GRef (GlobRef.ConstructRef cstr,_) -> constructor ?loc cstr l
        | GRef (GlobRef.ConstRef _ as c, _) when GlobRef.equal c (Lazy.force coq_inacc) ->
          let inacc = List.hd (List.tl l) in
          PUInac inacc
        | _ ->
          user_err_loc
            (loc, "pattern_of_glob_constr",
             str "Cannot interpret " ++ pr_glob_constr_env env sigma c ++ str " as a constructor")
      end
  (* | GLetIn (Name id as na',b,None,e) when is_gvar id e && na = Anonymous ->
   *    (\* A canonical encoding of aliases *\)
   *    DAst.get (cases_pattern_of_glob_constr na' b) *)
    | _ -> user_err_loc (loc, "pattern_of_glob_constr", str ("Cannot interpret globalized term as a pattern"))
  in DAst.map_with_loc aux gc

let program_type p = EConstr.it_mkProd_or_LetIn p.program_arity p.program_sign

let interp_pat env notations ?(avoid = ref Id.Set.empty) p pat =
  let sigma = Evd.from_env env in
  let vars = (Id.Set.elements !avoid) (* (ids_of_pats [p])) *) in
  (* let () = Feedback.msg_debug (str"Variables " ++ prlist_with_sep spc pr_id vars) in *)
  let tys = List.map (fun _ -> EConstr.mkProp) vars in
  let impls = List.map (fun _ -> []) vars in
  (* let () = Feedback.msg_debug (str"Internalizing " ++ pr_constr_expr p) in *)
  let ienv = try compute_internalization_env env sigma Variable vars tys impls with Not_found ->
    anomaly (str"Building internalization environment")
  in
  let vars, tys, impls, ienv =
    match p with
    | Some (p, _) ->
      let ty = program_type p in
      let ienv =
        try compute_internalization_env env sigma ~impls:ienv Recursive [p.program_id] [ty] [p.program_impls]
        with Not_found -> anomaly (str"Building internalization environment")
      in
      (p.program_id :: vars, ty :: tys, p.program_impls :: impls, ienv)
    | None -> (vars, tys, impls, ienv)
  in
  let nctx =
    List.map2 (fun id ty -> Context.Named.Declaration.LocalAssum (Context.annotR id, EConstr.Unsafe.to_constr ty)) vars tys
  in
  let env = Environ.push_named_context nctx env in
  let gc =
    Metasyntax.with_syntax_protection (fun () ->
      List.iter (Metasyntax.set_notation_for_interpretation (Environ.push_named_context nctx env) ienv) notations;
      try Constrintern.intern_gen Pretyping.WithoutTypeConstraint ~impls:ienv env sigma pat
      with Not_found -> anomaly (str"Internalizing pattern")) ()
  in
  try
    match p with
    | Some ({ program_id = id }, patnames) ->
      DAst.with_loc_val (fun ?loc g ->
          let fn, args =
            match g with
            | GApp (fn, args) -> fn, args
            | _ -> DAst.make ?loc g, []
          in
          DAst.with_loc_val (fun ?loc gh ->
              match gh with
              | GVar fid when Id.equal fid id ->
                let rec aux args patnames =
                  match args, patnames with
                  | a :: args, patname :: patnames ->
                    pattern_of_glob_constr env sigma avoid patname a :: aux args patnames
                  | a :: args, [] ->
                    pattern_of_glob_constr env sigma avoid Anonymous a :: aux args []
                  | [], _ -> []
                in aux args patnames
              | _ ->
                user_err_loc (loc, "interp_pats",
                              str "Expecting a pattern for " ++ Id.print id))
            fn) gc
    | None -> [pattern_of_glob_constr env sigma avoid Anonymous gc]
  with Not_found -> anomaly (str"While translating pattern to glob constr")

let rename_away_from ids pats =
  let rec aux ?loc pat =
    match pat with
    | PUVar (id, true) when Id.Set.mem id !ids ->
      let id' = next_ident_away id ids in
      PUVar (id', true)
    | PUVar (id, _) -> pat
    | PUCstr (c, n, args) -> PUCstr (c, n, List.map (DAst.map_with_loc aux) args)
    | PUInac c -> pat
    | PUEmpty -> pat
  in
  List.map (DAst.map_with_loc aux) pats

let interleave_implicits impls pats =
  let rec aux impls pats =
    match impls, pats with
    | Some id :: impls, pats -> DAst.make (PUVar (id, false)) :: aux impls pats
    | None :: impls, pat :: pats -> pat :: aux impls pats
    | None :: _, [] -> []
    | [], pats -> pats
  in aux impls pats

let interp_eqn env notations p eqn =
  let avoid = ref Id.Set.empty in
  let whereid = ref (Nameops.add_suffix p.program_id "_abs_where") in
  let patnames =
    List.rev_map (fun decl -> Context.Rel.Declaration.get_name decl) p.program_sign
  in
  let impls =
    List.map (fun a ->
        if Impargs.is_status_implicit a then Some (Impargs.name_of_implicit a) else None)
      p.program_implicits
  in
  let interp_pat notations = interp_pat env notations ~avoid in
  let rec aux notations curpats (pat, rhs) =
    let loc, pats =
      match pat with
      | SignPats pat ->
        avoid := Id.Set.union !avoid (ids_of_pats (Some p.program_id) [pat]);
        let loc = Constrexpr_ops.constr_loc pat in
        let pats = interp_pat notations (Some (p, patnames)) pat in
        loc, pats
      | RefinePats pats ->
        let patids = ref (ids_of_pats None pats) in
        let curpats = rename_away_from patids curpats in
        avoid := Id.Set.union !avoid !patids;
        let loc = Constrexpr_ops.constr_loc (List.hd pats) in
        let pats = List.map (interp_pat notations None) pats in
        let pats = List.map (fun x -> List.hd x) pats in
        let pats =
          (* At the toplevel only, interleave using the implicit
             status of the function arguments *)
          if curpats = [] then interleave_implicits impls pats
          else curpats @ pats in
        loc, pats
    in
    (* let () = check_linearity env pats in *)
    (loc, pats, Option.map (interp_rhs notations pats) rhs)
  and aux2 notations (pat, rhs) =
    (pat, Option.map (interp_rhs' notations) rhs)
  and interp_rhs' notations = function
    | Refine (c, eqs) ->
      let interp c =
        let wheres, c = CAst.with_loc_val (interp_constr_expr notations) c in
        if not (List.is_empty wheres) then
          user_err_loc (Constrexpr_ops.constr_loc c, "interp_eqns",
                        str"Pattern-matching lambdas not allowed in refine");
        c
      in
      Refine (List.map interp c, map (aux2 notations) eqs)
    | Program (c, (w, nts)) ->
       let notations = nts @ notations in
       let w = interp_wheres avoid w notations in
       let w', c =
         match c with
         | ConstrExpr c ->
            let wheres, c = CAst.with_loc_val (interp_constr_expr notations) c in
            wheres, ConstrExpr c
         | GlobConstr c -> [], GlobConstr c
         | Constr c -> [], Constr c
       in
       Program (c, (List.append w' w, nts))
    | Empty i -> Empty i
  and interp_rhs notations curpats = function
    | Refine (c, eqs) ->
      let interp c =
        let wheres, c = CAst.with_loc_val (interp_constr_expr notations) c in
        if not (List.is_empty wheres) then
          user_err_loc (Constrexpr_ops.constr_loc c, "interp_eqns",
                        str"Pattern-matching lambdas not allowed in refine");
        c
      in
      Refine (List.map interp c, map (aux notations curpats) eqs)
    | Program (c, (w, nts)) ->
       let w = interp_wheres avoid w (nts @ notations) in
       let w', c =
         match c with
         | ConstrExpr c ->
            let wheres, c = CAst.with_loc_val (interp_constr_expr notations) c in
            wheres, ConstrExpr c
         | GlobConstr c -> [], GlobConstr c
         | Constr c -> [], Constr c
       in
       Program (c, (List.append w' w, nts))
    | Empty i -> Empty i
  and interp_wheres avoid w notations =
    let interp_where (((loc,id),nested,b,t,reca) as p,eqns) =
      Dumpglob.dump_reference ~loc "<>" (Id.to_string id) "def";
      p, map (aux2 notations) eqns
    in List.map interp_where w
  and interp_constr_expr notations ?(loc=default_loc) c =
    let wheres = ref [] in
    let rec aux' ids ?(loc=default_loc) c =
      match c with
      (* | CApp ((None, { CAst.v = CRef (qid', ie) }), args)
       *      when qualid_is_ident qid' && Id.equal (qualid_basename qid') p.program_id ->
       *    let id' = qualid_basename qid' in
       *    (match p.program_rec with
       *     | None | Some (Structural _) -> CAst.make ~loc c
       *     | Some (WellFounded (_, _, r)) ->
       *       let args =
       *         List.map (fun (c, expl) -> CAst.with_loc_val (aux' ids) c, expl) args in
       *       let c = CApp ((None, CAst.(make ~loc (CRef (qid', ie)))), args) in
       *       let arg = CAst.make ~loc (CApp ((None, CAst.make ~loc c), [chole id' loc])) in
       *       arg) *)
      | CHole (k, i, Some eqns) when Genarg.has_type eqns (Genarg.rawwit wit_equations_list) ->
        let eqns = Genarg.out_gen (Genarg.rawwit wit_equations_list) eqns in
        let id = !whereid in
        let () = whereid := Nameops.increment_subscript id in
        let () = avoid := Id.Set.add id !avoid in
        let eqns = List.map (aux2 notations) eqns in
        let () =
          wheres := (((loc, id), None, [], None, None), eqns) :: !wheres;
        in Constrexpr_ops.mkIdentC id
      | _ -> map_constr_expr_with_binders Id.Set.add
             (fun avoid -> CAst.with_loc_val (aux' avoid)) ids (CAst.make ~loc c)
    in
    let c' = aux' !avoid ~loc c in
    !wheres, c'
  in aux notations [] eqn

let is_recursive i : 'a wheres -> bool = fun eqs ->
  let rec occur_eqn (_, rhs) =
    match rhs with
    | Some (Program (c,w)) ->
      (match c with
      | ConstrExpr c -> occur_var_constr_expr i c || occurs w
      | GlobConstr c -> occurs w
      | Constr _ -> occurs w)
    | Some (Refine (c, eqs)) ->
       List.exists (occur_var_constr_expr i) c || occur_eqns eqs
    | _ -> false
  and occur_eqns eqs = List.exists occur_eqn eqs
  and occurs_notations nts =
    List.exists (fun nt -> occur_var_constr_expr i nt.Vernacexpr.decl_ntn_interp) nts
  and occurs eqs =
    List.exists (fun (_,eqs) -> occur_eqns eqs) (fst eqs) || occurs_notations (snd eqs)
  in occurs eqs
