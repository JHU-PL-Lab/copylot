open Batteries;;
(* open Jhupllib;; *)
open Analysis_grammar;;
open Analysis_lookup_basis;;
open Analysis_lookup_dph;;
open Analysis_lookup_edge_functions;;
open Analysis_lexical_relations;;


open State;;
(* open Program_state;; *)
open Stack_element;;
(* open Dph.Terminus.T;; *)
open Dph.Stack_action.T;;
(* open Pds_reachability_types_stack;; *)

module Reachability =
  Pds_reachability.Make
    (Basis)
    (Dph)
    (Pds_reachability_work_collection_templates.Work_stack)
;;

type pds =
  {
    lookup_analysis: Reachability.analysis;
    relations: relation_map_record
  };;

let empty rmr =
  let analysis =
  Reachability.empty ()
  |> Reachability.add_edge_function global_edge_function
  in
  {lookup_analysis = analysis; relations = rmr}
;;

let add_cfg_edge edge pds =
  let Cfg.Edge (src, dst) = edge in
  let rmr = pds.relations in
  let edge_function = per_cfg_edge_function rmr src dst in
  let analysis' = Reachability.add_edge_function edge_function pds.lookup_analysis in
  {pds with lookup_analysis = analysis'}
;;

let get_value state=
  match state with
  | Program_state _ | Answer_memory _ -> None
  | Answer_value v -> Some v
;;

let lookup_value ps x pds =
  let analysis' = Reachability.add_start_state (Program_state ps) [Push (Lookup_value_variable x)] pds.lookup_analysis in
  let closed = Reachability.fully_close analysis' in
  let reachables = Reachability.get_reachable_states (Program_state ps) [] closed in
  let values = Enum.filter_map get_value reachables in
  (values, {pds with lookup_analysis = closed})
;;

let lookup_memory ps y pds =
  let analysis' = Reachability.add_start_state (Program_state ps) [Push (Lookup_memory_variable y)] pds.lookup_analysis in
  let closed = Reachability.fully_close analysis' in
  let reachables = Reachability.get_reachable_states (Program_state ps) [] closed in
  let values = Enum.filter_map get_value reachables in
  (values, {pds with lookup_analysis = closed})
;;

let lookup_memory_location ps m pds =
  let analysis' = Reachability.add_start_state (Program_state ps) [Push (Lookup_memory m); Push Lookup_dereference] pds.lookup_analysis in
  let closed = Reachability.fully_close analysis' in
  let reachables = Reachability.get_reachable_states (Program_state ps) [] closed in
  let values = Enum.filter_map get_value reachables in
  (values, {pds with lookup_analysis = closed})
;;
