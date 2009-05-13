(* Ocsimore
 * Copyright (C) 2005 Piero Furiesi Jaap Boender Vincent Balat
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
This is the wiki component of Ocsimore.

@author Jaap Boender
@author Piero Furiesi
@author Vincent Balat
*)


open Wiki_sql.Types
open User_sql.Types


let (>>=) = Lwt.bind


(* An exception raised when we register two wikis at the same path.
   The first two strings are the description of the conflicting wikis,
   the third string is the path *)
exception Wiki_already_registered_at_path of (string * string) * string


(* Create a wiki that is supposed not to exist already *)
let really_create_wiki ~title ~descr ?path ?staticdir ?(boxrights = true)
    ~author
    ?(admins=[basic_user author]) ?(readers = [basic_user Users.anonymous])
    ?wiki_css ~container_text
    () =
  let path_string = Ocsimore_lib.bind_opt
    path (Ocsigen_lib.string_of_url_path ~encode:true)
  in
  (* We check that no wiki is already registered at the same path *)
  Ocsimore_lib.lwt_bind_opt path_string
    (fun path -> Wiki_sql.iter_wikis
       (fun { wiki_descr = wiki; wiki_pages = path' } ->
          if path' = Some path then
            Lwt.fail (Wiki_already_registered_at_path ((wiki, descr), path))
          else
            Lwt.return ())
    ) >>= fun _ ->
  (* Notice that there is a theoretical race condition in the code below,
     when the container wikibox receives its rights, in the case this
     container has changed between the creation of the wiki and the moments
     the rights are added *)
  Wiki_sql.new_wiki ~title ~descr ~pages:path_string
     ~boxrights ?staticdir ~container_text ~author ()
   >>= fun (wiki_id, _wikibox_container) ->

   (* Putting users in groups *)
   (* Admins *)
   Users.add_list_to_group ~l:admins ~group:(apply_parameterized_group
                           Wiki_data.wiki_admins wiki_id) >>= fun () ->
   (* Readers *)
   Users.add_list_to_group ~l:readers ~group:(apply_parameterized_group
                Wiki_data.wiki_wikiboxes_grps.grp_reader wiki_id) >>= fun () ->
   Users.add_list_to_group ~l:readers ~group:(apply_parameterized_group
                Wiki_data.wiki_files_grps.grp_reader wiki_id) >>= fun () ->
   Users.add_list_to_group ~l:readers ~group:(apply_parameterized_group
                Wiki_data.wiki_css_grps.grp_reader wiki_id) >>= fun () ->

   (match wiki_css with
      | None -> Lwt.return ()
      | Some css -> Wiki_sql.set_css_for_wiki
          ~wiki:wiki_id ~author (Some css)
   ) >>= fun () ->

   Lwt.return wiki_id


let new_wikitextbox ~sp ~sd ~wiki ~author ~comment ~content () =
  Wiki_data.can_create_wikiboxes ~sp ~sd wiki
  >>= function
    | true -> Wiki_sql.new_wikibox ~wiki ~author ~comment ~content
        ~content_type:Wiki_sql.WikiCreole ()
    | false -> Lwt.fail Ocsimore_common.Permission_denied


(* Checks that [boxversion] is the current version of the wikibox *)
let modified_wikibox ~wikibox ~boxversion =
  Wiki_sql.current_wikibox_version wikibox
  >>= function
    | None -> Lwt.return None (* This case is not supposed to happen *)
    | Some curversion ->
        if curversion > boxversion then
          Lwt.return (Some curversion)
        else
          Lwt.return None


(** Exception raised when the content of a wikibox cannot be found *)
exception Unknown_box of wikibox * int32 option

let wikibox_content ~sp ~sd ?version (wid, _ as wb) =
  Wiki_sql.get_wikibox_data ?version ~wikibox:wb ()
  >>= fun result ->
  match result with
    | None -> Lwt.fail (Unknown_box (wb, version))
    | Some (_com, _a, cont, _d, ct, ver) ->
        (match ct with
           | Wiki_sql.WikiCreole -> Wiki_data.can_read_wikitext ~sp ~sd ~wb
           | Wiki_sql.Css -> Wiki_data.can_read_generic_css ~sp ~sd wid
        ) >>= function
          | true -> Lwt.return (ct, cont, ver)
          | false -> Lwt.fail Ocsimore_common.Permission_denied

let wikibox_content' ~sp ~sd ?version wikibox =
  wikibox_content ~sp ~sd ?version wikibox >>= fun (_, cont, ver) ->
  Lwt.return (cont, ver)


let save_wikibox ~enough_rights ~sp ~sd ~wb ~content ~content_type =
  enough_rights >>= function
    | true ->
        Users.get_user_id sp sd
        >>= fun user ->
        Wiki_sql.update_wikibox ~wikibox:wb ~author:user ~comment:""
          ~content ~content_type

    | false -> Lwt.fail Ocsimore_common.Permission_denied


(* XXX we should not allow overwriting a box containing a css *)
let save_wikitextbox ~sp ~sd ~wb ~content = save_wikibox ~sp ~sd ~wb
  ~enough_rights:(Wiki_data.can_write_wikitext ~sp ~sd ~wb)
  ~content_type:Wiki_sql.WikiCreole ~content

(* Saving the css of a wiki or of a wikipage. Notice that we do not
   currently check that the box passed as argument is indeed the css
   for the wiki or the wikipage. *)
let save_wikicssbox ~sp ~sd ~wb ~wiki ~content = save_wikibox ~sp ~sd ~wb
  ~enough_rights:(Wiki_data.can_write_wikicss ~sp ~sd ~wiki)
  ~content_type:Wiki_sql.Css ~content

let save_wikipagecssbox ~sp ~sd ~wb ~wiki ~page ~content =
  save_wikibox ~sp ~sd ~wb
    ~enough_rights:(Wiki_data.can_write_wikipagecss ~sp ~sd ~wiki ~page)
    ~content_type:Wiki_sql.Css ~content
