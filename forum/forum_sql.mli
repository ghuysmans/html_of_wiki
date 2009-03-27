(* Ocsimore
 * Copyright (C) 2005
 * Laboratoire PPS - Universit� Paris Diderot - CNRS
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)
(**
   @author Piero Furiesi
   @author Jaap Boender
   @author Vincent Balat
   @author Boris Yakobowski
*)


type forum

(** returns forum id *)
val get_id : forum -> int32

(** returns forum from id *)
val of_id : int32 -> forum

(** returns forum id as a string *)
val forum_id_s : forum -> string

(** create a new forum. [?arborescent] is true by default. 
    Setting it to false will prevent to comment comments. *)
val new_forum : 
  title:string -> 
  descr:string -> 
  ?arborescent:bool -> 
  unit ->
  forum Lwt.t

(** inserts a message in a forum. 
    [?moderated] and [?sticky] are false by default. *)
val new_message :
  forum_id:forum ->
  author_id:int32 ->
  ?subject:string ->
  ?parent_id:int32 ->
  ?moderated:bool ->
  ?sticky:bool ->
  text:string ->
  int32 Lwt.t

(** delete or undelete a message *)
val set_deleted :
  message_id:int32 -> deleted:bool -> unit Lwt.t
  
(** set ou unset sticky flag on a message *)
val set_sticky :
  message_id:int32 -> sticky:bool -> unit Lwt.t
  
(** set or unset moderated flag on a message *)
val set_moderated :
  message_id:int32 -> moderated:bool -> unit Lwt.t
  
(** Find forum information, given its id or title *)
val find_forum: 
  ?forum_id:forum -> 
  ?title:string -> 
  unit -> 
  (forum * string * string * bool * bool * bool) Lwt.t

(** returns the list of forums *)
val get_forums_list : unit ->
  (forum * string * string * bool * bool * bool) list Lwt.t
  
(** returns id, subject, author, datetime, text,
    and moderated, deleted, sticky status of a message *)
val get_message : 
  message_id:int32 -> 
 (int32 * string option * int32 * CalendarLib.Calendar.t * string * 
    bool * bool * bool) Lwt.t
  

(*
(** returns None|Some id of prev & next thread in the same forum *)
val thread_get_neighbours :
  frm_id:forum ->  
  thr_id:int32 -> 
  role:role -> 
  (int32 option * int32 option) Lwt.t

(** returns None|Some id of prev & next message in the same thread *)
val message_get_neighbours :
  frm_id:forum ->  
  msg_id:int32 -> 
  role:role -> 
  (int32 option * int32 option) Lwt.t

(** returns the threads list of a forum, ordered cronologycally
    (latest first), with max [~limit] items and skipping first
    [~offset] rows.  A list elt is (thr_id, subject, author, datetime,
    hidden status). *)
val forum_get_threads_list :
  frm_id:forum -> 
  ?offset:int64 -> 
  ?limit:int64 -> 
  role:role -> 
  unit ->
  (int32 * string * string * CalendarLib.Calendar.t * bool) list Lwt.t

val thread_get_messages_with_text :
  thr_id:int32 -> 
  ?offset:int64 -> 
  ?limit:int64 -> 
  role:role ->
  ?bottom:int32 -> 
  unit ->
  (forum * string * string * CalendarLib.Calendar.t * bool * bool) list Lwt.t
(** as above, but in tree form *)

val thread_get_messages_with_text_forest :
  thr_id:int32 -> 
  ?offset:int64 -> 
  ?limit:int64 ->
  ?top:int32 -> 
  ?bottom:int32 -> 
  role:role -> 
  unit ->
  (forum * 
     string * 
     string * 
     CalendarLib.Calendar.t * 
     bool * 
     bool * 
     int32 * 
     int32) Ocsimore_lib.tree list Lwt.t

val get_latest_messages:
  frm_ids:forum list -> 
  limit:int64 -> 
  unit ->
  (forum * string * string) list Lwt.t

  *)