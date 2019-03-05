From Equations Require Import Classes EqDec DepElim NoConfusion HoTTUtil.

Local Open Scope list_scope.

(** Tactic to solve EqDec goals, destructing recursive calls for the recursive 
  structure of the type and calling instances of eq_dec on other types. *)
Hint Extern 2 (@EqDecPoint ?A ?x) =>
  lazymatch goal with
  | [ H : forall y, ( x = _ ) + ( _ <> _ ) |- _ ] => exact H
  | [ H : forall y, dec_eq x y |- _ ] => exact H
  end : typeclass_instances.

Ltac eqdec_one x y :=
  let good := intros -> in
  let contrad := let Hn := fresh in
   intro Hn; right; red; simplify_dep_elim; apply Hn; reflexivity in
  try match goal with
       | [ H : forall z, dec_eq x z |- _ ] =>
         case (H y); [good|contrad]
        | [ H : forall z, ( x = z ) + ( _ ) |- _ ] =>
          case (H y); [good|contrad]
         | _ =>
           tryif unify x y then idtac (* " finished " x y *)
           else (case (eq_dec_point (x:=x) y); [good|contrad])
  end.

Ltac eqdec_loop t u :=
  match t with
  | context C [ ?t ?x ] =>
    match u with
    | context C [ ?u ?y] => eqdec_loop t u; eqdec_one x y
    end
   | _ => eqdec_one t u
  end.

Ltac eqdec_proof := try red; intros;
  match goal with
    |- dec_eq ?x ?y =>
    revert y; induction x; intros until y; depelim y;
    match goal with
      |- dec_eq ?x ?y => eqdec_loop x y
    end
   | |- ( ?x = ?y ) + ( _ ) =>
    revert y; induction x; intros until y; depelim y;
    match goal with
      |- ( ?x = ?y ) + ( _ ) => eqdec_loop x y
    end
  end; try solve[left; reflexivity | right; red; simplify_dep_elim].

(** Standard instances. *)

Instance unit_eqdec : EqDec Unit. 
Proof. eqdec_proof. Defined.

(* TODO These instance proofs should use eqdec_proof. *)

Require Import HoTT.Basics.Decidable.

Require Import HoTT.Types.Bool.
Definition Bool_rect := Bool_ind.

Instance bool_eqdec : EqDec Bool.
Proof. unfold EqDec. intros; destruct x,y; try (apply inl; reflexivity).
apply inr; intro.
  refine (
    match X in _ = b return
      match b with
      | true => Unit
      | false => _
      end
    with
    | idpath => tt
    end).
apply inr; intro.
  refine (
    match X in _ = b return
      match b with
      | false => Unit
      | true => _
      end
    with
    | idpath => tt
    end).
Defined.

Require Import HoTT.Spaces.Nat.
Instance nat_eqdec : EqDec nat.
Proof. unfold EqDec. intros.
  destruct (dec_paths x y).
  - rewrite p; apply inl; reflexivity.
  - apply inr; intro. destruct n. rewrite X; reflexivity. Defined.

Polymorphic Instance prod_eqdec {A B} `(EqDec A) `(EqDec B) : EqDec (prod A B).
Proof. eqdec_proof. Defined.

Polymorphic Instance sum_eqdec {A B} `(EqDec A) `(EqDec B) : EqDec (A + B).
Proof. eqdec_proof. Defined.

Polymorphic Instance list_eqdec {A} `(EqDec A) : EqDec (list A).
Proof. eqdec_proof. Defined.

Local Set Equations With UIP.

Polymorphic Instance sigma_uip {A B} `(UIP A) `(forall x, UIP (B x)) : UIP {x : A & B x}.
Proof.
  red. intros [x p] [y q]. repeat (simplify * || intro). reflexivity.
Defined.

Polymorphic Instance sigma_eqdec {A B} `(EqDec A) `(forall x, EqDec (B x)) : EqDec {x : A & B x}.
Proof.
  eqdec_proof.
Defined.

Polymorphic Definition eqdec_sig@{i} {A : Type@{i}} {B : A -> Type@{i}}
            `(EqDec A) `(forall a, EqDec (B a)) :
  EqDec@{k} (sigma A B).
Proof.
  intros. intros [x0 x1] [y0 y1].
  case (eq_dec x0 y0). intros ->. case (eq_dec x1 y1). intros ->. left. reflexivity.
  intros. right. red. apply simplification_sigma2_uip@{i Set}. apply n.
  intros. right. red. apply simplification_sigma1@{i Set}.
  intros e _; revert e. apply n.
Defined.

Existing Instance eqdec_sig.

Polymorphic Definition uip_sig@{i} {A : Type@{i}} {B : A -> Type@{i}}
            `(UIP A) `(forall a, UIP (B a)) :
  UIP@{i} (sigma@{i} A B).
Proof.
  intros. intros x y <-. destruct x.
  refine (eq_simplification_sigma1_dep_dep@{i Set} _ _ _ _ _).
  intros e'. destruct (uip eq_refl e'). simpl.
  intros e'. destruct (uip eq_refl e'). constructor.
Defined.

Existing Instance uip_sig.
