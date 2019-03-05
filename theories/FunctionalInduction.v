(**********************************************************************)
(* Equations                                                          *)
(* Copyright (c) 2009-2019 Matthieu Sozeau <matthieu.sozeau@inria.fr> *)
(**********************************************************************)
(* This file is distributed under the terms of the                    *)
(* GNU Lesser General Public License Version 2.1                      *)
(**********************************************************************)

From Equations Require Import EqDec DepElim.

(** The [FunctionalInduction f] typeclass is meant to register functional induction
   principles associated to a function [f]. Such principles are automatically 
   generated for definitions made using [Equations]. *)

Polymorphic
Class FunctionalInduction {A : Type} (f : A) :=
  { fun_ind_prf_ty : Type; fun_ind_prf : fun_ind_prf_ty }.

(** The tactic [funind c Hc] applies functional induction on the application 
   [c] which must be of the form [f args] where [f] has a [FunctionalInduction]
   instance. [Hc] is the name given to the call, used to generate hypothesis names. *)

Ltac funind c Hcall := 
  match c with
    context C [ ?f ] =>
      let x := constr:(fun_ind_prf (f:=f)) in
        (let prf := eval simpl in x in
         let p := context C [ prf ] in
         let prf := fresh in
         let call := fresh in
           assert(prf:=p) ;
           (* Abstract the call *)
           set(call:=c) in *; generalize (idpath : call = c); clearbody call ; intro Hcall ;
           (* Now do dependent elimination and simplifications *)
           dependent induction prf ; simplify_IH_hyps ; 
           (* Use the simplifiers for the constant to get a nicer goal. *)
           try simpc f in * ; try on_last_hyp ltac:(fun id => simpc f in id ; noconf id))
        || fail 1 "Internal error in funind"
  end || fail "Maybe you didn't declare the functional induction principle for" c.

Ltac funind_call f H :=
  on_call f ltac:(fun call => funind call H).

(** The [FunctionalElimination f] class declares elimination principles produced
   from the functional induction principle for [f] to be used directly to eliminate
   a call to [f]. This is the preferred method of proving results about a function. 
   [n] is the number of binders for parameters, predicates and methods of the 
   eliminator.
   *)

Polymorphic
Class FunctionalElimination {A : Type} (f : A) (fun_elim_ty : Type) (n : nat) :=
  fun_elim : fun_elim_ty.

Ltac make_refine n c :=
  match constr:(n) with
  | 0 => uconstr:(c)
  | S ?n => make_refine n uconstr:(c _)
  end.

Ltac constr_head c :=
  let rec aux c :=
      match c with
      | ?f _ => aux f
      | ?f => f
      end
  in aux c.

Ltac with_last_secvar_aux tac :=
  match goal with
   [ H : _ |- _ ] => is_secvar H; tac H
  end.

Ltac with_last_secvar tac orelse := 
  with_last_secvar_aux tac + (* No section variables *) orelse.

Ltac get_elim c :=
  match c with
  | context [?f] => constr:(fun_elim (f:=f))
  end.

Ltac clear_non_secvar := repeat
  match goal with
  | [ H : _ |- _ ] => tryif is_secvar H then fail else clear H
  end.

Ltac remember_let H :=
  lazymatch goal with
  | [ H := ?body : ?type |- _ ] =>
    generalize (idpath : body = H); clearbody H
  end.

Ltac unfold_packcall packcall :=
  lazymatch goal with
    |- ?x = ?y -> ?P =>
    let y' := eval unfold packcall in y in
        change (x = y' -> P)
  end.

Ltac simplify_IH_hyps' := repeat
  match goal with
  | [ hyp : context [ block ] |- _ ] =>
    cbn beta in hyp; eqns_specialize_eqs_block hyp;
    cbn beta iota delta[eq_rect_r eq_rect] zeta in hyp
  end.

Ltac make_packcall packcall c :=
  match goal with
  | [ packcall : ?type |- _ ] => change (let _ := c in type) in (type of packcall)
  end.

Ltac funelim_sig_tac c tac :=
  let elimc := get_elim c in
  let packcall := fresh "packcall" in
  let packcall_fn := fresh "packcall_fn" in
  let elimfn := match elimc with fun_elim (f:=?f) => constr:(f) end in
  let elimn := match elimc with fun_elim (n:=?n) => constr:(n) end in
  block_goal;
  uncurry_call elimfn c packcall packcall_fn;
  remember_let packcall_fn; unfold_packcall packcall;
  (refine (eq_simplification_sigma1_nondep_dep _ _ _ _ _) ||
   refine (eq_simplification_sigma1_dep _ _ _ _ _) ||
   refine (Id_simplification_sigma1_dep _ _ _ _ _) ||
   refine (Id_simplification_sigma1_nondep_dep _ _ _ _ _));
  let H := fresh "eqargs" in
  let Heq := fresh "Heqcall" in intros H Heq;
  try (rewrite <- Heq; clear Heq); revert_until H; revert H;
  subst packcall_fn; clearbody packcall;
  make_packcall packcall elimfn;
  with_last_secvar ltac:(fun eos => move packcall before eos)
                          ltac:(move packcall at top);
  revert_until packcall; block_goal;
  cbv zeta in packcall; revert packcall; curry;
  let elimt := make_refine elimn elimc in
  unshelve refine_ho elimt; intros;
  cbv beta; simplify_dep_elim; intros_until_block;
  simplify_dep_elim;
  cbn beta iota delta [eq_rect_dep_r Id_rect_r eq_rect Id_rect pack_sigma_eq pack_sigma_eq_nondep
                                     pack_sigma_Id pack_sigma_Id_nondep] in *;
  simplify_IH_hyps'; (* intros _; *)
  unblock_goal; simplify_IH_hyps; tac c.

Ltac funelim_constr c := funelim_sig_tac c ltac:(fun _ => idtac).

Tactic Notation "funelim" uconstr(p) :=
  let call := fresh "call" in
  set (call:=p);
  lazymatch goal with
    [ call := ?fp |- _ ] =>
    subst call; funelim_constr fp
  end.

Ltac apply_args c elimc k :=
    match c with
    | _ ?a ?b ?c ?d ?e ?f => k uconstr:(elimc a b c d e f)
    | _ ?a ?b ?c ?d ?e => k uconstr:(elimc a b c d e)
    | _ ?a ?b ?c ?d => k uconstr:(elimc a b c d)
    | _ ?a ?b ?c => k uconstr:(elimc a b c)
    | _ ?a ?b => k uconstr:(elimc a b)
    | _ ?a => k uconstr:(elimc a)
    end.

Ltac get_first_elim c :=
  match c with
  | ?f ?a ?b ?c ?d ?e ?f => get_elim (f a b c d e f)
  | ?f ?a ?b ?c ?d ?e => get_elim (f a b c d e)
  | ?f ?a ?b ?c ?d => get_elim (f a b c d)
  | ?f ?a ?b ?c => get_elim (f a b c)
  | ?f ?a ?b => get_elim (f a b)
  | ?f ?a => get_elim (f a)
  end.

(** An alternative tactic that does not generalize over the arguments.
    BEWARE: It might render the goal unprovable. *)
Ltac apply_funelim c :=
  let elimc := get_first_elim c in
  let elimfn := match elimc with fun_elim (f:=?f) => constr:(f) end in
  let elimn := match elimc with fun_elim (n:=?n) => constr:(n) end in
  let elimt := make_refine elimn elimc in
  apply_args c elimt ltac:(fun elimc =>
                             unshelve refine_ho elimc; cbv beta).

(** A special purpose database used to prove the elimination principle. *)

Create HintDb funelim.

(** Solve reflexivity goals. *)

Hint Extern 0 (_ = _) => reflexivity : funelim.

(** Specialize hypotheses begining with equalities. *)

Ltac specialize_hyps :=
  match goal with
    [ H : forall _ : ?x = ?x, _ |- _ ] => 
    specialize (H (@idpath _ x)); unfold paths_ind in H ; simpl in H
  | [ H : forall _ : @Id _ ?x ?x, _ |- _ ] =>
    specialize (H (@idpath _ x)); unfold Id_rect_dep_r, Id_rect_r, Id_rect in H ; simpl in H
  end.

Hint Extern 100 => specialize_hyps : funelim.

(** Destruct conjunctions everywhere, starting with the hypotheses.
   This tactic allows to close functional induction proofs involving
   multiple nested and/or mutual recursive definitions. *)

(** TODO: make it generic, won't work with another logic *)

Lemma uncurry_conj (A B C : Prop) : (A /\ B -> C) -> (A -> B -> C).
Proof. intros H a b. exact (H (conj a b)). Defined.

Lemma uncurry_prod (A B C : Type) : (A * B -> C) -> (A -> B -> C).
Proof. intros H a b. exact (H (pair a b)). Defined.

Ltac specialize_mutual_nested := 
  match goal with
    [ H : _ /\ _ |- _ ] => destruct H
  | [ |- _ /\ _ ] => split
  | [ H : _ * _ |- _ ] => destruct H
  | [ |- _ * _ ] => split
  end.

Hint Extern 50 => specialize_mutual_nested : funelim.

Ltac specialize_mutual :=
  match goal with
    [ H : _ /\ _ |- _ ] => destruct H
  | [ H : _ * _ |- _ ] => destruct H
  (* Fragile, might render later goals unprovable *)
  | [ H : ?X -> _, H' : ?X |- _ ] =>
    match X with
      | forall (_ : _), _ => specialize (H H')
    end
  | [ H : (?A /\ ?B) -> ?C |- _ ] => apply (uncurry_conj A B C) in H
  end.

Ltac specialize_mutfix := repeat specialize_mutual.

(** Destruct existentials, including [existsT]'s. *)

(* Hint Extern 101 => progress (destruct_exists; try (is_ground_goal; simplify_eqs)) : funelim. *)
