(**********************************************************************)
(* Equations                                                          *)
(* Copyright (c) 2009-2019 Matthieu Sozeau <matthieu.sozeau@inria.fr> *)
(**********************************************************************)
(* This file is distributed under the terms of the                    *)
(* GNU Lesser General Public License Version 2.1                      *)
(**********************************************************************)


(*i camlp4deps: "grammar/grammar.cma" i*)

DECLARE PLUGIN "equations_plugin"

open Constr
open Names
open Pp
open Refiner
open Constrexpr
open Stdarg
open Equations_common
open EConstr
open Ltac_plugin

let of82 = Proofview.V82.tactic
let wit_hyp = wit_var

TACTIC EXTEND decompose_app
| [ "decompose_app" ident(h) ident(h') constr(c) ] -> [ Extra_tactics.decompose_app h h' c ]
END

TACTIC EXTEND autounfold_ref
| [ "autounfold_ref" reference(myref) ] -> [ Extra_tactics.autounfold_ref myref ]
END

(* Sigma *)

open Proofview.Goal

TACTIC EXTEND get_signature_pack
| [ "get_signature_pack" hyp(id) ident(id') ] ->
     [ Sigma_types.Tactics.get_signature_pack id id' ]
END
      
TACTIC EXTEND pattern_sigma
| [ "pattern" "sigma" hyp(id) ] -> [ Sigma_types.Tactics.pattern_sigma id ]
END

TACTIC EXTEND curry
| [ "curry" hyp(id) ] -> [ Sigma_types.Tactics.curry_hyp id ]
| ["curry"] -> [ Sigma_types.Tactics.curry ]
END

TACTIC EXTEND curry_hyps
| [ "uncurry_hyps" ident(id) ] -> [ Sigma_types.uncurry_hyps id ]
END

TACTIC EXTEND uncurry_call
| [ "uncurry_call" constr(c) constr(c') ident(id) ident(id') ] -> [ Sigma_types.Tactics.uncurry_call c c' id id' ]
END

(* Depelim *)

TACTIC EXTEND dependent_pattern
| ["dependent" "pattern" constr(c) ] -> [
    Proofview.V82.tactic (Depelim.dependent_pattern c) ]
END

TACTIC EXTEND dependent_pattern_from
| ["dependent" "pattern" "from" constr(c) ] ->
    [ Proofview.V82.tactic (Depelim.dependent_pattern ~pattern_term:false c) ]
END

TACTIC EXTEND pattern_call
| [ "pattern_call" constr(c) ] -> [ Proofview.V82.tactic (Depelim.pattern_call c) ]
END

TACTIC EXTEND needs_generalization
| [ "needs_generalization" hyp(id) ] -> 
    [ Proofview.V82.tactic (fun gl ->
      if Depelim.needs_generalization gl id
      then tclIDTAC gl
      else tclFAIL 0 (str"No generalization needed") gl) ]
END

(* Equations *)

open Tacarg

TACTIC EXTEND solve_equations
| [ "solve_equations" tactic(destruct) tactic(tac) ] -> 
     [ of82 (Equations.solve_equations_goal (to82 (Tacinterp.tactic_of_value ist destruct))
                                            (to82 (Tacinterp.tactic_of_value ist tac))) ]
END

TACTIC EXTEND simp
| [ "simp" ne_preident_list(l) clause(c) ] -> 
    [ of82 (Principles_proofs.simp_eqns_in c l) ]
| [ "simpc" constr_list(l) clause(c) ] -> 
   [ of82 (Principles_proofs.simp_eqns_in
                        c
                        (dbs_of_constrs (List.map EConstr.Unsafe.to_constr l))) ]
END

open Syntax

open Pcoq.Prim

ARGUMENT EXTEND equation_user_option
PRINTED BY pr_r_equation_user_option
| [ "noind" ] -> [ OInd false ]
| [ "ind" ] -> [ OInd true ]
| [ "eqns" ] -> [ OEquations true ]
| [ "noeqns" ] -> [ OEquations false ]
END

ARGUMENT EXTEND equation_options
PRINTED BY pr_equation_options
| [ "(" ne_equation_user_option_list(l) ")" ] -> [ l ]
| [ ] -> [ [] ]
END

let pr_lident _ _ _ (loc, id) = Id.print id

ARGUMENT EXTEND lident
PRINTED BY pr_lident
| [ ident(i) ] -> [ (loc, i) ]
END


module Gram = Pcoq.Gram
module Vernac = Pcoq.Vernac_

type binders_argtype = Constrexpr.local_binder_expr list Genarg.uniform_genarg_type

let pr_raw_binders2 _ _ _ l = mt ()
let pr_glob_binders2 _ _ _ l = mt ()
let pr_binders2 _ _ _ l = mt ()

(* let wit_binders_let2 : binders_let2_argtype = *)
(*   Genarg.create_arg "binders_let2" *)

let wit_binders2 : binders_argtype =
  Genarg.create_arg "binders2"

let binders2 : local_binder_expr list Gram.entry =
  Pcoq.create_generic_entry Pcoq.uconstr "binders2" (Genarg.rawwit wit_binders2)

let binders2_val = Geninterp.register_val0 wit_binders2 None

let _ = Pptactic.declare_extra_genarg_pprule wit_binders2
  pr_raw_binders2 pr_glob_binders2 pr_binders2

type deppat_equations_argtype = Syntax.pre_equation list Genarg.uniform_genarg_type

let wit_deppat_equations : deppat_equations_argtype =
  Genarg.create_arg "deppat_equations"

let deppat_equations_val = Geninterp.register_val0 wit_deppat_equations None

let pr_raw_deppat_equations _ _ _ l = mt ()
let pr_glob_deppat_equations _ _ _ l = mt ()
let pr_deppat_equations _ _ _ l = mt ()

let deppat_equations : Syntax.pre_equation list Gram.entry =
  Pcoq.create_generic_entry Pcoq.uvernac "deppat_equations" (Genarg.rawwit wit_deppat_equations)

let _ = Pptactic.declare_extra_genarg_pprule wit_deppat_equations
  pr_raw_deppat_equations pr_glob_deppat_equations pr_deppat_equations

type deppat_elim_argtype = Constrexpr.constr_expr list Genarg.uniform_genarg_type

let wit_deppat_elim : deppat_elim_argtype =
 Genarg.create_arg "deppat_elim"

let deppat_elim_val = Geninterp.register_val0 wit_deppat_elim None

let pr_raw_deppat_elim _ _ _ l = mt ()
let pr_glob_deppat_elim _ _ _ l = mt ()
let pr_deppat_elim _ _ _ l = mt ()

let deppat_elim : Constrexpr.constr_expr list Gram.entry =
  Pcoq.create_generic_entry Pcoq.utactic "deppat_elim" (Genarg.rawwit wit_deppat_elim)

let _ = Pptactic.declare_extra_genarg_pprule wit_deppat_elim
  pr_raw_deppat_elim pr_glob_deppat_elim pr_deppat_elim

type equations_argtype = (pre_equations * Vernacexpr.decl_notation list) Genarg.uniform_genarg_type

let wit_equations : equations_argtype =
  Genarg.create_arg "equations"
let val_equations = Geninterp.register_val0 wit_equations None

let pr_raw_equations _ _ _ l = mt ()
let pr_glob_equations _ _ _ l = mt ()
let pr_equations _ _ _ l = mt ()

let equations : (pre_equations * Vernacexpr.decl_notation list) Gram.entry =
  Pcoq.create_generic_entry Pcoq.uvernac "equations" (Genarg.rawwit wit_equations)

let _ = Pptactic.declare_extra_genarg_pprule wit_equations
  pr_raw_equations pr_glob_equations pr_equations

(* preidents that are not interpreted focused *)
let interp_my_preident ist s = s

let make0 ?dyn name =
  let wit = Genarg.make0 name in
  let () = Geninterp.register_val0 wit dyn in
  wit

let wit_my_preident : string Genarg.uniform_genarg_type =
  make0 ~dyn:(Geninterp.val_tag (Genarg.topwit wit_string)) "my_preident"

let def_intern ist x = (ist, x)
let def_subst _ x = x
let def_interp ist x = Ftactic.return x

let register_interp0 wit f =
  let interp ist v =
    Ftactic.bind (f ist v)
      (fun v -> Ftactic.return (Geninterp.Val.inject (Geninterp.val_tag (Genarg.topwit wit)) v))
  in
  Geninterp.register_interp0 wit interp

let declare_uniform t =
  Genintern.register_intern0 t def_intern;
  Genintern.register_subst0 t def_subst;
  register_interp0 t def_interp

let () =
  declare_uniform wit_my_preident

let my_preident : string Gram.entry =
  Pcoq.create_generic_entry Pcoq.utactic "my_preident" (Genarg.rawwit wit_my_preident)

open Util
open Pcoq
open Constr
open Syntax

let _ = CLexer.add_keyword "λ"

GEXTEND Gram
  GLOBAL: operconstr pattern deppat_equations deppat_elim binders2 equations lident my_preident;

  my_preident:
    [ [ id = IDENT -> id ] ]
  ;
  binders2 : 
     [ [ b = binders -> b ] ]
  ;
  deppat_equations:
    [ [ l = LIST0 equation SEP ";" -> l ] ]
  ;

  deppat_elim:
    [ [ "["; l = LIST0 lconstr SEP "|"; "]" -> l ] ]
  ;

  operconstr:
    [ [ "λ"; "{" ; c = LIST1 equation SEP ";"; "}" ->
            CAst.make (CHole (None, Misctypes.IntroAnonymous,
                   Some (Genarg.in_gen (Genarg.rawwit Syntax.wit_equations_list) c))) ] ]
  ;

    
  identloc :
   [ [ id = ident -> (!@loc, id) ] ] ;

  equation:
    [ [ "|"; pats = LIST1 lconstr SEP "|"; r = rhs -> (RefinePats pats, r)
      | pat = pat; r = rhs -> (SignPats pat, r) ]
    ]
  ;

  pat:
    [ [ p = lconstr -> p ] ]
  ;

  refine:
    [ [ cs = LIST1 Constr.lconstr SEP "," -> cs
    ] ]
  ;

  wf_annot:
    [ [ "by"; IDENT "wf"; c = constr; rel = OPT constr -> Some (WellFounded (c, rel))
      | "by"; "struct"; id = OPT identloc -> Some (Structural id)
      | -> None
    ] ]
  ;

  proto:
   [ [
   id = lident; l = binders2; ":"; t = Constr.lconstr;
   reca = wf_annot; ":="; eqs = sub_equations -> (fun r -> ((id, r, l, Some t, reca), eqs))
   ] ]
  ;

  where_rhs:
    [ [ ntn = ne_lstring; ":="; c = constr;
        scopt = OPT [ ":"; sc = IDENT -> sc ] -> Inr (ntn, c, scopt)
      | p = proto -> Inl (p (Some Syntax.Nested)) ] ]
  ;

  where_clause:
    [ [ "where"; w = where_rhs -> w
      | "with"; p = proto -> Inl (p (Some Syntax.Mutual))
      | p = proto -> Inl (p None)
    ] ]
  ;
  wheres:
    [ [ l = LIST0 where_clause ->
      let rec aux = function
          | Inl w :: l -> let ws, ns = aux l in w :: ws, ns
          | Inr n :: l -> let ws, ns = aux l in ws, n :: ns
          | [] -> ([], [])
        in aux l
    ] ]
  ;

  local_where_rhs:
    [ [ ntn = ne_lstring; ":="; c = constr;
        scopt = OPT [ ":"; sc = IDENT -> sc ] -> Inr (ntn, c, scopt)
      | p = proto -> Inl (p (Some Syntax.Mutual)) ] ]
  ;
  local_where:
    [ [ "where"; w = local_where_rhs -> w
      | "with"; p = proto -> Inl (p (Some Syntax.Mutual))
    ] ]
  ;
  local_wheres:
    [ [ l = LIST0 local_where ->
      let rec aux = function
        | Inl w :: l -> let ws, ns = aux l in w :: ws, ns
        | Inr n :: l -> let ws, ns = aux l in ws, n :: ns
        | [] -> ([], [])
      in aux l
    ] ]
  ;
  rhs:
    [ [ ":=!"; id = identloc -> Some (Empty id)

     | [":=" -> () | "=>" -> () ]; c = Constr.lconstr; w = local_wheres ->
        Some (Program (ConstrExpr c, w))

     | ["with" -> [ () ] ]; refs = refine; [":=" -> [ () ] |"=>" -> [ () ] ];
       e = sub_equations -> Some (Refine (refs, e))
     | -> None
    ] ]
  ;

  sub_equations:
    [ [ "{"; l = deppat_equations; "}" -> l
      | l = deppat_equations -> l
    ] ]
  ;

  equations:
    [ [ p = proto; l = wheres -> let ws, nts = l in
                                 ((p None :: ws), nts) ] ]
  ;
  END


let classify_equations x =
  Vernacexpr.(VtStartProof ("Classic",Doesn'tGuaranteeOpacity,[]), VtLater)

VERNAC COMMAND EXTEND Define_equations CLASSIFIED AS SIDEFF
| [ "Equations" equation_options(opt) equations(eqns) ] ->
    [ Equations.equations ~poly:(Flags.is_universe_polymorphism ()) ~open_proof:false opt (fst eqns) (snd eqns) ]
END

VERNAC COMMAND EXTEND Define_equations_refine CLASSIFIED BY classify_equations
| [ "Equations?" equation_options(opt) equations(eqns) ] ->
    [ Equations.equations ~poly:(Flags.is_universe_polymorphism ()) ~open_proof:true opt (fst eqns) (snd eqns) ]
END

(* Dependent elimination using Equations. *)

type raw_elim_patterns = constr_expr list
type glob_elim_patterns = Tactypes.glob_constr_and_expr list
type elim_patterns = user_pats

let interp_elim_pattern env avoid s =
  Syntax.pattern_of_glob_constr env avoid Anonymous (* Should be id *) (fst s)

let interp_elim_patterns ist gl s =
  let sigma = project gl in
  let env = Goal.V82.env sigma gl.Evd.it in
  let avoid = ref (Names.Id.Map.domain ist.Geninterp.lfun) in
  sigma, List.map (interp_elim_pattern env avoid) s

let glob_elim_patterns ist s = List.map (Tacintern.intern_constr ist) s
let subst_elim_patterns s str = str

let pr_elim_patterns _ _ _ (s : elim_patterns) = Syntax.pr_user_pats (Global.env ()) (*FIXME*) s
let pr_raw_elim_patterns prc prlc _ (s : raw_elim_patterns) =
  Pp.prlist_with_sep (fun _ -> str "|") prc s
let pr_glob_elim_patterns prc prlc env (s : glob_elim_patterns) =
  Pp.prlist_with_sep (fun _ -> str "|") (fun x -> prc x) s

type elim_patterns_argtype = (raw_elim_patterns, glob_elim_patterns, elim_patterns) Genarg.genarg_type

(* let interp_elim_patterns ist gl l =
 *   match l with
 *     | ArgArg x -> x
 *     | ArgVar ({ CAst.v = id } as locid) ->
 *         (try int_list_of_VList (Id.Map.find id ist.lfun)
 *           with Not_found | CannotCoerceTo _ -> [interp_int ist locid])
 *
 * let interp_elim_patterns ist gl l =
 *   Tacmach.project gl , interp_occs ist gl l
 *
 * let wit_g_elim_patterns : elim_patterns_argtype =
 *   Genarg.create_arg "g_elim_patterns"
 *
 * let val_g_elim_patterns =
 *   Geninterp.register_val0 wit_g_elim_patterns None
 *
 * (\* let pr_raw_g_elim_patterns _ _ _ = Simplify.pr_elim_patterns
 *  * let pr_glob_g_elim_patterns _ _ _ = Simplify.pr_elim_patterns
 *  * let pr_g_elim_patterns _ _ _ = Simplify.pr_elim_patterns *\)
 *
 * let g_elim_patterns : raw_elim_patterns Pcoq.Entry.t =
 *   Pcoq.create_generic_entry Pcoq.utactic "g_elim_patterns"
 *     (Genarg.rawwit wit_g_elim_patterns)
 *
 * let _ = Pptactic.declare_extra_genarg_pprule wit_g_elim_patterns
 *   pr_raw_elim_patterns pr_glob_elim_patterns pr_elim_patterns *)

ARGUMENT EXTEND elim_patterns
  PRINTED BY pr_elim_patterns
  INTERPRETED BY interp_elim_patterns
  GLOBALIZED BY glob_elim_patterns
  SUBSTITUTED BY subst_elim_patterns
  RAW_PRINTED BY pr_raw_elim_patterns
  GLOB_PRINTED BY pr_glob_elim_patterns
  | [ deppat_elim(l) ] -> [ l ]
END

TACTIC EXTEND dependent_elimination
| [ "dependent" "elimination" ident(id) ] -> [ Depelim.dependent_elim_tac (Loc.make_loc (0, 0), id) ]
| [ "dependent" "elimination" ident(id) "as" elim_patterns(l) ] ->
   [ Depelim.dependent_elim_tac ~patterns:l (Loc.make_loc (0, 0), id) (* FIXME *) ]
END

(* Subterm *)


TACTIC EXTEND is_secvar
| [ "is_secvar" constr(x) ] ->
   [ enter (fun gl ->
     match kind (Proofview.Goal.sigma gl) x with
     | Var id when Termops.is_section_variable id -> Proofview.tclUNIT ()
     | _ -> Tacticals.New.tclFAIL 0 (str "Not a section variable or hypothesis")) ]
END

TACTIC EXTEND refine_ho
| [ "refine_ho" open_constr(c) ] -> [ Extra_tactics.refine_ho c ]
END

TACTIC EXTEND eqns_specialize_eqs
| [ "eqns_specialize_eqs" ident(i) ] -> [
    Proofview.V82.tactic (Depelim.specialize_eqs ~with_block:false i)
  ]
| [ "eqns_specialize_eqs_block" ident(i) ] -> [
    Proofview.V82.tactic (Depelim.specialize_eqs ~with_block:true i)
  ]
END

TACTIC EXTEND move_after_deps
| [ "move_after_deps" ident(i) constr(c) ] ->
 [Equations_common.move_after_deps i c ]
END

(** Deriving *)

VERNAC COMMAND EXTEND Derive CLASSIFIED AS SIDEFF
| [ "Derive" ne_ident_list(ds) "for" global_list(c) ] -> [
    let poly = Flags.is_universe_polymorphism () in
  Ederive.derive ~poly (List.map Id.to_string ds)
    (List.map (fun x -> x.CAst.loc, Smartlocate.global_with_alias x) c)
  ]
END


(* Simplify *)

type simplification_rules_argtype = Simplify.simplification_rules Genarg.uniform_genarg_type

let wit_g_simplification_rules : simplification_rules_argtype =
  Genarg.create_arg "g_simplification_rules"

let val_g_simplification_rules =
  Geninterp.register_val0 wit_g_simplification_rules None

let pr_raw_g_simplification_rules _ _ _ = Simplify.pr_simplification_rules
let pr_glob_g_simplification_rules _ _ _ = Simplify.pr_simplification_rules
let pr_g_simplification_rules _ _ _ = Simplify.pr_simplification_rules

let g_simplification_rules : Simplify.simplification_rules Gram.entry =
  Pcoq.create_generic_entry Pcoq.utactic "g_simplification_rules"
    (Genarg.rawwit wit_g_simplification_rules)

let _ = Pptactic.declare_extra_genarg_pprule wit_g_simplification_rules
  pr_raw_g_simplification_rules pr_glob_g_simplification_rules pr_g_simplification_rules

GEXTEND Gram
  GLOBAL: g_simplification_rules;

  g_simplification_rules:
    [ [ l = LIST1 simplification_rule_located -> l ] ]
  ;

  simplification_rule_located:
    [ [ r = simplification_rule -> (Some !@loc, r) ] ]
  ;

  simplification_rule:
    [ [ step = simplification_step -> Simplify.Step step
      | "?" -> Simplify.Infer_one
      | "<->" -> Simplify.Infer_direction
      | "*" -> Simplify.Infer_many
    ] ];

  simplification_step :
    [ [ "-" -> Simplify.Deletion false
      | "-!" -> Simplify.Deletion true
      | "<>" -> Simplify.NoCycle
      | "$" -> Simplify.NoConfusion []
      | "$"; "{"; rules = g_simplification_rules; "}" ->
        Simplify.NoConfusion rules
      | dir = direction -> Simplify.Solution dir
    ] ];

  direction:
    [ [ "->" -> Simplify.Left
      | "<-" -> Simplify.Right
    ] ];
END

(* We need these alias due to the limitations of parsing macros. *)
type simplification_rules = Simplify.simplification_rules
let pr_simplification_rules _ _ _ = Simplify.pr_simplification_rules

ARGUMENT EXTEND simplification_rules
PRINTED BY pr_simplification_rules
  | [ g_simplification_rules(l) ] -> [ l ]
END

TACTIC EXTEND simplify
| [ "simplify" simplification_rules(l) ] ->
  [ Simplify.simplify_tac l ]
| [ "simplify" ] ->
  [ Simplify.simplify_tac [] ]
END

TACTIC EXTEND mutual_fix
| [ "mfix" my_preident_list(li) int_list(l) ] -> [ Principles_proofs.mutual_fix li l ]
END

(* Register command *)

VERNAC COMMAND EXTEND Register CLASSIFIED AS SIDEFF
[ "Register" global(g) "as" global(quid) ] -> [
Equations_common.register_ref (CAst.with_val id (Libnames.qualid_of_reference quid))
 (CAst.with_val id (Libnames.qualid_of_reference g)) ]
END
