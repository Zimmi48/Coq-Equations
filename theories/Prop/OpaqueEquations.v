(**********************************************************************)
(* Equations                                                          *)
(* Copyright (c) 2009-2020 Matthieu Sozeau <matthieu.sozeau@inria.fr> *)
(**********************************************************************)
(* This file is distributed under the terms of the                    *)
(* GNU Lesser General Public License Version 2.1                      *)
(**********************************************************************)

(** This module sets the set constants of Equations to opaque mode so
  that computation is not possible inside Coq, the tactics need this
  to solve obligations. *)

Require Import Equations.Prop.DepElim.

Global Opaque simplification_sigma2_uip
       simplification_sigma2_dec_point
       simplification_K_uip
       simplify_ind_pack simplified_ind_pack.
