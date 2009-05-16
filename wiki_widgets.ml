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

open Language

open User_sql.Types
open Wiki_widgets_interface
open Wiki_sql.Types

let (>>=) = Lwt.bind


class wikibox_error_box =
object

  inherit Widget.widget_with_error_box as error_box

  method display_error_box ?classes ?message ?exn () =
    match exn with
      | Some (Wiki.Unknown_box ((w, i), ver)) ->
          error_box#display_error_box
            ?classes
            ~message:(Printf.sprintf
                        "The box %ld does not exist in wiki %s%s."
                        i (string_of_wiki w)
                        (match ver with
                           | None -> ""
                           | Some v -> Printf.sprintf " with version %ld" v))
            ?exn
            ()
      | Some Wiki_services.Page_already_exists ->
          error_box#display_error_box
            ?classes
            ~message:("This page has already been created \
                       (reload the page to see it).")
            ?exn
            ()
      | Some Wiki_services.Operation_insufficient_permissions ->
          error_box#display_error_box
            ?classes
            ~message:("Unable to perform the operation: insufficient permissions")
            ?exn
            ()
      | _ -> error_box#display_error_box ?classes ?message ?exn ()

end

class wikibox_aux (error_box : Widget.widget_with_error_box)
  : Wiki_widgets_interface.wikibox_aux =
object (self)

  method display_container ?(css={{ [] }}) ?(title="Ocsimore wiki") content =
    let title = Ocamlduce.Utf8.make title in
(*VVV � revoir : fichiers statiques *)
    {{
       <html xmlns="http://www.w3.org/1999/xhtml">[
         <head>[
           <title>title
           <script type="text/javascript" src="vm.js">[]
           <script type="text/javascript" src="eliom_obrowser.js">[]
           <script type="text/javascript" src="ocsimore.js">[]
             !css
         ]
         <body>content
       ]
     }}


  method display_wikiboxcontent ~bi ~wiki ~classes (content_type, content, _ver as wb) =
    match content_type, content with
      | Wiki_sql.WikiCreole, Some content ->
          Wiki_syntax.xml_of_wiki wiki bi content
          >>= fun x -> Lwt.return (classes, x)
      | _ -> self#display_raw_wikiboxcontent ~classes wb

  method display_raw_wikiboxcontent ~classes (content_type, content, _ver) =
    (match content_type, content with
       | Wiki_sql.WikiCreole, Some content ->
           Lwt.return {{ [<pre>{:Ocamlduce.Utf8.make content :}] }}
       | Wiki_sql.Css, None -> Lwt.return {{ [<em>"/* Deleted Css */"] }}
       | Wiki_sql.WikiCreole, None -> Lwt.return {{ [<em>"Deleted wikibox"] }}
       | Wiki_sql.Css, Some content  ->
           Lwt.return {{ [<pre>{:Ocamlduce.Utf8.make content :}]}}
    ) >>= fun x ->
    Lwt.return (classes, x)

  method display_basic_box ~classes content =
    let classe = Ocsimore_lib.build_class_attr classes in
    Lwt.return
      {{ <div class={: classe :}>content }}

end


class frozen_wikibox (error_box : Widget.widget_with_error_box)
  : Wiki_widgets_interface.frozen_wikibox =
object (self)

  inherit wikibox_aux error_box

  val frozen_wb_class = "frozen_wikibox"

  method display_frozen_wikibox ~bi ?(classes=[]) ~wikibox =
    Lwt.catch
      (fun () ->
         error_box#bind_or_display_error
           (Wiki.wikibox_content bi.bi_sp wikibox)
           (self#display_wikiboxcontent ~wiki:(fst wikibox) ~bi
              ~classes:(frozen_wb_class::classes))
           (self#display_basic_box)
      )
      (function
         | Ocsimore_common.Permission_denied ->
              Lwt.return
                (error_box#display_error_box
                   ~classes:(frozen_wb_class::classes)
                   ~message:"You are not allowed to see this content."
                   ())
         | e -> Lwt.fail e)
end;;



(** Displaying of a wikibox with viewing and/or editing rights. Takes
    as argument all the services needed to save modifications
    or navigate through viewing options *)
class dynamic_wikibox (error_box : Widget.widget_with_error_box)
(* (* Debugging code, to obtain useful error messages *)
   : Wiki_widgets_interface.interactive_wikibox =
   let *)
(
  action_edit_css,
  action_edit_wikibox,
  action_delete_wikibox,
  action_edit_wikibox_permissions,
  action_wikibox_history,
  action_css_history,
  action_old_wikibox,
  action_old_wikiboxcss,
  action_src_wikibox,
  action_send_wikiboxtext,
  action_send_css,
  action_send_wikibox_permissions,
  pagecss_service,
  action_create_page,
  action_create_css
) : Wiki_widgets_interface.interactive_wikibox =
(* = Wiki_services.services () in *)
object (self)

  inherit frozen_wikibox error_box

  val editform_class = "wikibox editform"
  val history_class = "wikibox history"
  val css_history_class = "wikibox history"
  val interactive_class = "wikibox editable"
  val oldwikibox_class = "wikibox editable oldversion"
  val srcwikibox_class = "wikibox editable src"
  val box_button_class = "boxbutton"
  val box_title_class = "boxtitle"
  val preview_class = "preview"
  val css_class = "editcss"


  method private box_menu ~bi ?cssmenu ?service ?(title = "") ((wid, _) as wb) =
    let sp = bi.bi_sp
    and preapply = Eliom_services.preapply in
    let history = preapply action_wikibox_history wb
    and edit = preapply action_edit_wikibox wb
    and delete = preapply action_delete_wikibox wb
    and edit_perm = preapply action_edit_wikibox_permissions wb
    in
    let view = Eliom_services.void_coservice' in
    (match cssmenu with
       | Some (CssWikipage page) -> (* Edition of the css for page [page] *)
           (Wiki_sql.get_css_wikibox_for_wikipage wid page >>= function
              | None -> Lwt.return (None, None)
              | Some wbcss ->
                  let wbcss = (wbcss, Some page) in
                  let edit = preapply action_edit_css (wb, (wbcss, None))
                  and history = preapply action_css_history (wb, wbcss)
                  in
                  Lwt.return
                    (Some (history, {{ "page css history" }}),
                     Some (edit, {{ "edit page css" }}))
           )

       | Some CssWiki -> (* Edition of the global css for [wiki] *)
           (Wiki_sql.get_css_wikibox_for_wiki wid >>= function
              | None -> Lwt.return (None, None)
              | Some wbcss ->
                  let wbcss = (wbcss, None) in
                  let edit = preapply action_edit_css (wb, (wbcss, None))
                  and history = preapply action_css_history (wb, wbcss)
                  in
                  Lwt.return
                    (Some (history, {{ "wiki css history" }}),
                     Some (edit, {{ "edit wiki css" }}))
           )


       | None -> Lwt.return (None, None)
    ) >>= fun (history_css, edit_css) ->
    let service = match service with
      | None -> None
      | Some Menu_View -> Some view
      | Some Menu_Edit -> Some edit
      | Some Menu_EditPerm -> Some edit_perm
      | Some Menu_History -> Some history
      | Some Menu_EditCss ->
          (match edit_css with
             | Some (edit_css, _) -> Some edit_css
             | None -> None
          )
      | Some Menu_HistoryCss ->
          (match history_css with
             | Some (history_css, _) -> Some history_css
             | None -> None
          )
    in
    let l = [
      (delete, {{ "delete" }});
      (edit, {{ "edit" }});
      (view, {{ "view" }});
    ] in
    (Wiki_data.can_admin_wikibox ~sp ~wb >>= function
      | true  -> Lwt.return ((edit_perm, {{ "edit permissions" }})::l)
      | false -> Lwt.return l
    ) >>= fun l ->
    let l = match edit_css with
      | Some mi -> mi::l
      | None -> l
    in
    let l = match history_css with
      | Some mi -> mi :: l
      | None -> l
    in
    let title = Ocamlduce.Utf8.make title in
    Lwt.return
      {{ [ {: Eliom_duce_tools.menu ~sp ~classe:[box_button_class]
              (history, {{ "history" }}) l ?service :}
           <p class={: box_title_class :}>title
         ]  }}

  method display_menu_box ~bi ~classes ?service ?cssmenu ?title ~wb content =
    let classes = Ocsimore_lib.build_class_attr classes in
    self#box_menu ~bi ?cssmenu ?service ?title wb >>=
    fun menu -> Lwt.return
      {{ <div class={: classes :}>[
           !menu
           <div>content ]}}


  (* Wikitext in editing mode *)
  method display_wikitext_edit_form ~bi ~classes ?(rows=25) ?(cols=80) ~previewonly ~wb:(wid, wbid as wb) (content, version) =
    let content = match content with
      | None -> "<<|  Deleted >>"
      | Some content -> content
    and sp = bi.bi_sp in
    Wiki.modified_wikibox wb version >>=
    (function
       | Some curversion -> Lwt.return
           (curversion,
            {{ [ <em>['Warning: ']
                 !{: Ocamlduce.Utf8.make !messages.wikitext_edition_conflict1 :}
                 <br>[] <br>[]
             ]
             }},
            {{ [ <br>[]
                 <b> [ <em> ['Warning: ']
                       !{: Ocamlduce.Utf8.make
                           !messages.wikitext_edition_conflict1 :}
                     ]
                 <br>[]
               ] }} )

       | None -> Lwt.return (version, {{ [] }}, {{ [] }})
    ) >>= fun (curversion, warning1, warning2)  ->
    let draw_form (actionname,(((widname, wbidname),versionname),contentname)) =
      {{ [ <p>[!warning1
               {: Eliom_duce.Xhtml.user_type_input string_of_wiki
                  ~input_type:{: "hidden" :}
                  ~name:widname ~value:wid () :}
               {: Eliom_duce.Xhtml.int32_input ~input_type:{: "hidden" :}
                  ~name:wbidname ~value:wbid () :}
               {: Eliom_duce.Xhtml.int32_input ~input_type:{: "hidden" :}
                  ~name:versionname ~value:curversion () :}
               {: Eliom_duce.Xhtml.textarea ~name:contentname ~rows ~cols
                  ~value:(Ocamlduce.Utf8.make content) () :}
               <br>[]
               !warning2
               {: Eliom_duce.Xhtml.string_button
                  ~name:actionname ~value:"preview" {{ "Preview" }} :}
               !{: if previewonly then []
                   else
                     [Eliom_duce.Xhtml.string_button ~name:actionname
                        ~value:"save" {{ "Save" }} ] :}
              ]] }}
    in
    Lwt.return
      (classes,
       Eliom_duce.Xhtml.post_form ~a:{{ { accept-charset="utf-8" } }}
         ~service:action_send_wikiboxtext ~sp draw_form ())

  (* Wikitext in editing mode, with an help box on the syntax of the wiki *)
  method display_wikitext_edit_form_help ~bi ~classes ?rows ?cols ~previewonly ~wb data=
    Wiki_services.get_admin_wiki ()
    >>= fun { wiki_id = admin_wiki } ->
    Wiki_sql.get_wikipage_info ~wiki:admin_wiki ~page:"wikisyntax-help"
    >>= fun { wikipage_dest_wiki = wid_help; wikipage_wikibox = wbid_help } ->
    error_box#bind_or_display_error
      (Wiki.wikibox_content bi.bi_sp (wid_help, wbid_help))
      (self#display_wikiboxcontent ~wiki:admin_wiki ~bi ~classes:["wikihelp"])
      (self#display_basic_box)
    >>= fun b ->
    self#display_wikitext_edit_form ~bi ~classes:[] ?rows ?cols
      ~previewonly ~wb data
    >>= fun (_, f) ->
    Lwt.return (classes, {{ [ b f ] }})


  (* Css in editing mode *)
  method display_css_edit_form ~bi ~classes ?(rows=25) ?(cols=80) ~wb:(wid, wbid) ~wbcss:(widcss, wbidcss as wbcss) ~wikipage (content, boxversion) =
    let content = match content with
      | None -> "/* Deleted CSS */"
      | Some content -> content
    and sp = bi.bi_sp in
    Wiki.modified_wikibox wbcss boxversion >>=
    (function
       | Some curversion -> Lwt.return
           (curversion,
            {{ [ <em>['Warning: ']
                 !{: Ocamlduce.Utf8.make !messages.css_edition_conflict :}
                 <br>[] <br>[]
             ]
             }} )

       | None -> Lwt.return (boxversion, {{ [] }} )
    ) >>= fun (curversion, warning)  ->
    let draw_form (((widname, wbidname), (((widcssname, wbidcssname), wikipagename), versionname)), contentname) =
      {{ [ <p>[!warning
               {: Eliom_duce.Xhtml.user_type_input
                  string_of_wiki ~input_type:{: "hidden" :}
                  ~name:widname ~value:wid () :}
               {: Eliom_duce.Xhtml.int32_input ~input_type:{: "hidden" :}
                  ~name:wbidname ~value:wbid () :}
               {: Eliom_duce.Xhtml.user_type_input
                  string_of_wiki ~input_type:{: "hidden" :}
                  ~name:widcssname ~value:widcss () :}
               {: Eliom_duce.Xhtml.int32_input ~input_type:{: "hidden" :}
                  ~name:wbidcssname ~value:wbidcss () :}
               !{: match wikipage with
                   | None -> []
                   | Some page ->
                       [ Eliom_duce.Xhtml.string_input ~name:wikipagename
                           ~input_type:{: "hidden" :} ~value:page () ]
                :}
               {: Eliom_duce.Xhtml.int32_input ~input_type:{: "hidden" :}
                  ~name:versionname ~value:curversion () :}
               {: Eliom_duce.Xhtml.textarea ~name:contentname ~rows ~cols
                  ~value:(Ocamlduce.Utf8.make content) () :}
               <br>[]
               !{: [Eliom_duce.Xhtml.button ~button_type:{: "submit" :}
                      {{ "Save" }}] :}
              ] ] }}
    in
    Lwt.return
      (classes,
       {{ [ {: Eliom_duce.Xhtml.post_form ~a:{{ { accept-charset="utf-8" } }}
               ~service:action_send_css ~sp draw_form () :} ] }})


  (* Edition of the permissions of a wiki *)
  method display_edit_perm_form ~bi ~classes wb =
    Wiki_sql.get_wikibox_info wb >>= fun { wikibox_uid = uid } ->
    snd (Users.GenericRights.helpers_admin_writer_reader
       ~prefix:"wiki" ~name:"edit-wikibox" Wiki_data.wikibox_grps) uid
    >>= fun form ->
    let form = Eliom_duce.Xhtml.post_form ~a:{{ { accept-charset="utf-8" } }}
      ~service:action_send_wikibox_permissions ~sp:bi.bi_sp form
      ()
    in
    Lwt.return (classes, {{ [ form ] }})

  (* Auxiliary method to factorize some code *)
  method private menu_box_aux ?title ?service cl wb ~bi ~classes ?cssmenu content=
    self#display_menu_box ~classes:(cl::classes) ?service ?title ~bi ?cssmenu ~wb
      content

  method private menu_edit_wikitext (w, b as wb) =
    let title = Printf.sprintf "Edit - Wiki %s, box %ld" (string_of_wiki w) b in
    self#menu_box_aux ~title ~service:Menu_Edit editform_class wb

  method private menu_edit_perm (w, b as wb) =
    let title = Printf.sprintf "Permissions - Wiki %s, box %ld"
      (string_of_wiki w) b in
    self#menu_box_aux ~title ~service:Menu_EditPerm editform_class wb

  method private menu_wikitext_history (w, b as wb) =
    let title = Printf.sprintf "History - Wiki %s, box %ld" (string_of_wiki w) b in
    self#menu_box_aux ~title ~service:Menu_History history_class wb

  method private menu_css_history ((w, _) as wb) page =
    let title = Printf.sprintf "CSS history, wiki %s, %s"
      (string_of_wiki w) (self#css_wikibox_text page) in
    self#menu_box_aux ~title ~service:Menu_HistoryCss css_history_class wb

  method private menu_view =
    self#menu_box_aux ~service:Menu_View interactive_class

  method private menu_old_wikitext (w, b as wb) version =
    let title = Printf.sprintf "Old version - Wiki %s, box %ld, version %ld"
      (string_of_wiki w) b version in
    self#menu_box_aux ~title oldwikibox_class wb

  method private menu_old_css ((w, _) as wb) page =
    let title = Printf.sprintf "Old css version, wiki %s, %s"
      (string_of_wiki w) (self#css_wikibox_text page) in
    self#menu_box_aux ~title oldwikibox_class wb

  method private menu_src_wikitext (w, b as wb) version =
    let title = Printf.sprintf "Source - Wiki %s, box %ld, version %ld"
      (string_of_wiki w) b version in
    self#menu_box_aux ~title srcwikibox_class wb

  method private menu_edit_css ((w, _) as wb) page =
    let title = Printf.sprintf "CSS for wiki %s, %s"
      (string_of_wiki w) (self#css_wikibox_text page) in
    self#menu_box_aux ~title ~service:Menu_EditCss css_class wb

  method private css_wikibox_text = function
    | None -> "global stylesheet"
    | Some "" -> "main page"
    | Some page ->  "page " ^ page


  method display_wikitext_history ~bi ~classes ~wb l =
    let sp = bi.bi_sp in
    Lwt_util.map
      (fun (version, _comment, author, date) ->
         User_sql.get_basicuser_data (User_sql.Types.user_from_sql author)
         >>= fun { user_fullname = author } ->
         Lwt.return
           {{ [ !{: Int32.to_string version :}'. '
                !{: CalendarLib.Printer.Calendar.to_string date :}' '
                <em>[ 'by ' !{: author :} ]' '
                {:  Eliom_duce.Xhtml.a ~sp ~service:action_old_wikibox
                   {{ "view" }} (wb, version) :}
                ' ''('
                {: Eliom_duce.Xhtml.a ~sp ~service:action_src_wikibox
                   {{ "source" }} (wb, version) :}
                ')'
                <br>[]
              ]
            }})
      l
    >>= fun l ->
    Lwt.return (classes, {{ map {: l :} with i -> i }})

  method display_css_history ~bi ~classes ~wb ~wbcss ~wikipage l =
    let sp = bi.bi_sp
    and wbcss = (wbcss, wikipage)
    in
    Lwt_util.map
      (fun (version, _comment, author, date) ->
         User_sql.get_basicuser_data (User_sql.Types.user_from_sql author)
         >>= fun { user_fullname = author } ->
           Lwt.return
             {{ [ !{: Int32.to_string version :}'. '
                  !{: CalendarLib.Printer.Calendar.to_string date :}' '
                  <em>[ 'by ' !{: author :} ]' '
                  {:  Eliom_duce.Xhtml.a ~sp ~service:action_old_wikiboxcss
                     {{ "view" }} (wb, (wbcss, version)) :}
                  <br>[]
                ]
              }})
      l
    >>= fun l ->
    Lwt.return (classes, {{ map {: l :} with i -> i }})


  method display_interactive_wikibox_aux ~bi ?(classes=[]) ?rows ?cols ?cssmenu (wid, _ as wb) =
    let sp = bi.bi_sp in
    let override = Wiki_widgets_interface.get_override_wikibox ~sp in
    match override with
      | Some (wb', override) when wb = wb' ->
          self#display_overriden_interactive_wikibox ~bi ~classes ?rows ?cols
            ?cssmenu ~wb_loc:wb ~override
      | _ ->
          Wiki_data.can_write_wikibox ~sp ~wb >>= function
            | true ->
                error_box#bind_or_display_error
                  (Wiki.wikibox_content sp wb)
                  (self#display_wikiboxcontent ~classes ~wiki:wid
                     ~bi:(Wiki_widgets_interface.add_ancestor_bi wb bi))
                  (self#menu_view ~bi ?cssmenu wb)
                >>= fun r ->
                Lwt.return (r, true)

             | false ->
                 Wiki_data.can_read_wikibox ~sp ~wb >>= function
                   | true ->
                       error_box#bind_or_display_error
                         (Wiki.wikibox_content sp wb)
                         (self#display_wikiboxcontent ~classes ~wiki:wid
                            ~bi:(Wiki_widgets_interface.add_ancestor_bi wb bi))
                         (self#display_basic_box)
                       >>= fun r ->
                       Lwt.return (r, true)

                   | false ->
                       Lwt.return
                       (error_box#display_error_box
                          ~classes:(frozen_wb_class::classes)
                          ~message:"You are not allowed to see this content."
                          (),
                        false)


  method display_overriden_interactive_wikibox ~bi ?(classes=[]) ?rows ?cols ?cssmenu ~wb_loc ~override =
    let sp = bi.bi_sp in
    match override with
      | EditWikitext wb ->
(*TRY:
          error_box#bind_or_display_error
            (Wiki.wikibox_content' wb)
            (fun (content, version as cv) ->
               self#display_wikiboxcontent ~wiki:(fst wb_loc)
                 ~classes:[] ~bi:(Wiki_widgets_interface.add_ancestor_bi wb bi)
                 (Wiki_sql.WikiCreole, content, version)
               >>= fun (_, pp) ->
               self#display_basic_box ~classes:[] pp
               >>= fun preview ->
               self#display_wikitext_edit_form_help ~classes:[]
                 ~bi ?cols ?rows ~previewonly:true ~wb cv
               >>= fun (_, form) ->
                 Lwt.return
                   (classes,
                    {{ [ preview
                         <div class="editwidget">form ] }})
            )
            (self#menu_edit_wikitext ~bi ?cssmenu wb_loc)
          >>= fun r ->
          Lwt.return (r, true)
*)
          error_box#bind_or_display_error
            (Wiki.wikibox_content' bi.bi_sp wb)
            (self#display_wikitext_edit_form_help ~bi ?cols ?rows
               ~previewonly:true ~wb ~classes)
            (self#menu_edit_wikitext ~bi ?cssmenu wb_loc)
          >>= fun r ->
          Lwt.return (r, true)

      | EditCss ((wbcss, wikipage), css) ->
          error_box#bind_or_display_error
            (match css with
               | None -> Wiki.wikibox_content' sp wbcss
               | Some (content, version) ->
                   Lwt.return (Some content, version)
            )
            (self#display_css_edit_form ~bi ?cols ?rows
               ~wb:wb_loc ~wbcss ~wikipage ~classes)
            (self#menu_edit_css ~bi ?cssmenu wb_loc wikipage)
          >>= fun r ->
          Lwt.return (r, true)

      | EditPerms wb ->
          error_box#bind_or_display_error
            (Lwt.return wb)
            (self#display_edit_perm_form ~bi ~classes)
            (self#menu_edit_perm ~bi ?cssmenu wb_loc)
          >>= fun r ->
          Lwt.return (r, true)

      | PreviewWikitext (wb, (content, version)) ->
          error_box#bind_or_display_error
            (Lwt.return (Some content, version))
            (fun (content, version as cv) ->
               self#display_wikiboxcontent ~wiki:(fst wb_loc)
                 ~classes:[] ~bi:(Wiki_widgets_interface.add_ancestor_bi wb bi)
                 (Wiki_sql.WikiCreole, content, version)
               >>= fun (_, pp) ->
               self#display_basic_box ~classes:[] pp
               >>= fun preview ->
               self#display_wikitext_edit_form_help ~classes:[]
                 ~bi ?cols ?rows ~previewonly:false ~wb cv
               >>= fun (_, form) ->
                 Lwt.return
                   (classes,
                    {{ [ <p class={: box_title_class :}>"Preview"
                         preview
                         !form ] }})
            )
            (self#menu_edit_wikitext ~bi ?cssmenu wb_loc)
          >>= fun r ->
          Lwt.return (r, true)

      | History wb ->
          error_box#bind_or_display_error
            (Wiki_sql.get_history wb)
            (self#display_wikitext_history ~bi ~classes ~wb)
            (self#menu_wikitext_history ~bi ?cssmenu wb_loc)
          >>= fun r ->
          Lwt.return (r, true)

      | CssHistory (wbcss, wikipage) ->
          error_box#bind_or_display_error
            (Wiki_sql.get_history wbcss)
            (self#display_css_history ~bi ~classes ~wb:wb_loc ~wbcss ~wikipage)
            (self#menu_css_history ~bi ?cssmenu wb_loc wikipage)
          >>= fun r ->
          Lwt.return (r, true)

      | Oldversion (wb, version) ->
          error_box#bind_or_display_error
            (Wiki.wikibox_content ~sp ~version wb)
            (self#display_wikiboxcontent ~classes ~wiki:(fst wb_loc)
               ~bi:(Wiki_widgets_interface.add_ancestor_bi wb bi))
            (self#menu_old_wikitext ~bi ?cssmenu wb_loc version)
          >>= fun r ->
          Lwt.return (r, true)

      | CssOldversion ((wbcss, page), version) ->
          error_box#bind_or_display_error
            (Wiki.wikibox_content ~sp ~version wbcss)
            (self#display_wikiboxcontent ~classes ~wiki:(fst wb_loc)
               ~bi:(Wiki_widgets_interface.add_ancestor_bi wbcss bi))
            (self#menu_old_css ~bi ?cssmenu wb_loc page)
          >>= fun r ->
          Lwt.return (r, true)

      | Src (wb, version)->
          error_box#bind_or_display_error
            (Wiki.wikibox_content ~sp ~version wb)
            (self#display_raw_wikiboxcontent ~classes)
            (self#menu_src_wikitext ~bi ?cssmenu wb_loc version)
          >>= fun r ->
          Lwt.return (r, true)

      | Error error ->
          Lwt.return
            (error_box#display_error_box ~classes ~exn:error (), false)


   method display_interactive_wikibox ~bi ?(classes=[]) ?rows ?cols ?cssmenu wb =
     self#display_interactive_wikibox_aux ~bi ?rows ?cols ~classes ?cssmenu wb
     >>= fun (r, _allowed) -> Lwt.return r


   method css_header ~bi ?(admin=false) ?page wiki =
     let sp = bi.bi_sp in
     let css_url_service service args = Eliom_duce.Xhtml.css_link
       (Eliom_duce.Xhtml.make_uri service sp args) () in
     let css_url path = css_url_service (Eliom_services.static_dir sp) path in

     if admin then
       Lwt.return
         {{ [ {:css_url [Ocsimore_lib.ocsimore_admin_dir; "ocsiwikistyle.css"]:}
              {:css_url [Ocsimore_lib.ocsimore_admin_dir; "ocsiwikiadmin.css"]:}
            ] }}
     else
       let css= css_url [Ocsimore_lib.ocsimore_admin_dir;"ocsiwikistyle.css"] in
       (match Wiki_services.find_servwikicss wiki with
          | None -> Lwt.return {{ [ css ] }}
          | Some wikicss_service ->
              Wiki_sql.get_css_for_wiki wiki
              >>= function
                | Some _ -> Lwt.return (* encoding? *)
                    {{ [ css  {: css_url_service wikicss_service ():} ]}}
                | None -> Lwt.return {{ [ css ] }}
       )
       >>= fun css ->
       match page with
         | None -> Lwt.return css
         | Some page ->
             Wiki_sql.get_css_for_wikipage ~wiki ~page >>= function
               | None -> Lwt.return css
               | Some _ -> Lwt.return
                   {{ [ !css
                        {: css_url_service pagecss_service (wiki, page)
                           (* encoding? *) :}
                      ]}}


(* Displaying of an entire page. We essentially render the page,
   and then include it inside its container *)
   method display_wikipage ~bi ~wiki ~page =
     let sp = bi.bi_sp in
     Wiki_sql.get_wiki_info_by_id wiki
     >>= fun wiki_info ->
     Lwt.catch
       (fun () ->
          (* We render the wikibox for the page *)
          Wiki_sql.get_wikipage_info wiki page
          >>= fun { wikipage_dest_wiki = wiki'; wikipage_wikibox = box;
                    wikipage_title = title } ->
          let bi = default_bi ~sp in
          self#display_interactive_wikibox_aux ~bi ~cssmenu:(CssWikipage page)
            (wiki', box)
          >>= fun (subbox, allowed) ->
          Lwt.return ({{ [ subbox ] }},
                      (if allowed then Wiki_widgets_interface.Page_displayable
                       else            Wiki_widgets_interface.Page_403),
                      title)
       )
       (function
          | Not_found ->
              (* No page. We create a default page, which will be
                 inserted into the container *)
              let draw_form (wikiidname, pagename) =
                {{ [<p>[
                       {: Eliom_duce.Xhtml.user_type_input
                          string_of_wiki ~input_type:{: "hidden" :}
                          ~name:wikiidname ~value:wiki () :}
                       {: Eliom_duce.Xhtml.string_input ~name:pagename
                          ~input_type:{: "hidden" :} ~value:page () :}
                       {: Eliom_duce.Xhtml.string_input
                          ~input_type:{: "submit" :} ~value:"Create it!" () :}
                     ]] }}
              in
              Users.in_group ~sp 
                ~group:(apply_parameterized_group
                          Wiki_data.wiki_wikipages_creators wiki) ()
              >>= fun c ->
              let form =
                if c then
                  {{ [ {: Eliom_duce.Xhtml.post_form ~service:action_create_page
                          ~sp draw_form () :} ] }}
                else {{ [] }}
              and err_msg = !Language.messages.Language.page_does_not_exist
              in
              Lwt.return
                ({{ [ <p>{:err_msg:} !form ] }},
                 Wiki_widgets_interface.Page_404,
                 None)
          | e -> Lwt.fail e
       )
       >>= fun (subbox, err_code, title) ->
       Wiki_widgets_interface.set_page_displayable sp err_code;

       (* We render the container *)
       let bi = { (default_bi ~sp) with bi_subbox = Some subbox } in
       self#display_interactive_wikibox ~bi ~cssmenu:CssWiki
         (wiki, wiki_info.wiki_container)

       >>= fun pagecontent ->
       self#css_header ~bi ~admin:false ~page wiki

       >>= fun css ->
       let title = (match title with
                      | Some title -> title
                      | None -> wiki_info.wiki_descr)
       and code = match err_code with
         | Wiki_widgets_interface.Page_displayable -> 200
         | Wiki_widgets_interface.Page_404 -> 404
         | Wiki_widgets_interface.Page_403 -> 403
       in
       Lwt.return (self#display_container ~css ~title {{ [pagecontent] }},
                   code)

   method send_wikipage ~bi ~wiki ~page =
     let sp = bi.bi_sp in
     Wiki_sql.get_wiki_info_by_id wiki
     >>= fun wiki_info ->
     (* if there is a static page, and should we send it ? *)
     Lwt.catch
       (fun () ->
          match wiki_info.wiki_staticdir with
            | Some d ->
                Wiki_services.send_static_file sp wiki_info.wiki_id d page
            | None -> Lwt.fail Eliom_common.Eliom_404)
       (function
          | Eliom_common.Eliom_404 ->
              self#display_wikipage ~bi ~wiki ~page
              >>= fun (html, code) ->
              Eliom_duce.Xhtml.send ~sp ~code html
          | e -> Lwt.fail e)

end

(* BY: Helper functions, which factorizes a bit of code in the functions
   below. Some of them  (eg. extract_wiki_id) are very mysterious:
   - I believe there is always a field "wiki" present, so the
   exception handler is useless
   - Why do we need to extract this value since we have a default ?
*)
let extract_wiki_id args default =
  try wiki_of_string (List.assoc "wiki" args)
  with Failure _ | Not_found -> default
and extract_https args =
  try match List.assoc "protocol" args with
    | "http" -> Some false
    | "https" -> Some true
    | _ -> None
  with Not_found -> None


let register_wikibox_syntax_extensions (widget : Wiki_widgets_interface.interactive_wikibox) (error_box : Widget.widget_with_error_box) =
Wiki_syntax.add_extension ~name:"wikibox" ~wiki_content:true
  (fun wiki_id bi args c ->
     Wikicreole.Block
       (try
         let wiki = extract_wiki_id args wiki_id in
         try
           let box = Int32.of_string (List.assoc "box" args) in
           if Ancestors.in_ancestors (wiki, box) bi.bi_ancestors then
             Lwt.return {{ [ {: error_box#display_error_box
                                ~message:"Wiki error: loop of wikiboxes" () :} ] }}
           else
             (match c with
                | None -> Lwt.return None
                | Some c ->
                    Wiki_syntax.xml_of_wiki wiki_id bi c
                    >>= fun r -> Lwt.return (Some r)
             ) >>=fun subbox ->
             widget#display_interactive_wikibox
               ?rows:(Ocsimore_lib.int_of_string_opt
                        (Ocsimore_lib.list_assoc_opt "rows" args))
               ?cols:(Ocsimore_lib.int_of_string_opt
                        (Ocsimore_lib.list_assoc_opt "cols" args))
               ?classes:(try Some [List.assoc "class" args]
                         with Not_found -> None)
               ~bi:{bi with
                      bi_ancestors =
                   Ancestors.add_ancestor (wiki, box) bi.bi_ancestors;
                      bi_subbox = subbox}
               (wiki, box)
             >>= fun b ->
               Lwt.return {{ [ b ] }}
         with Not_found ->
           Lwt.return {{ [ <code>"<<wikibox>>" ] }}
       with
         | Failure _ ->
             Lwt.return {{ [ {: error_box#display_error_box
                                ~message:"Wiki error: error in wikibox extension" () :} ] }}
  ));

Wiki_filter.add_preparser_extension ~name:"wikibox"
  (fun wid (sp, father) args c ->
     (try
        let wid = extract_wiki_id args wid in
        try (* If a wikibox is already specified, there is nothing to do *)
          ignore (List.assoc "box" args); Lwt.return None
        with Not_found ->
          Users.get_user_id ~sp
          >>= fun userid ->
          let _englobing_wb = (wid, father) in
          Wiki_data.can_create_wikiboxes ~sp wid >>= function
            | true ->
                Wiki.new_wikitextbox ~sp
                  ~wiki:wid
                  ~author:userid
                  ~comment:(Printf.sprintf "Subbox of wikibox %s, wiki %ld"
                              (string_of_wiki wid) father)
                  ~content:"**//new wikibox//**" ()
                  (* XXX Must copy the permissions of englobing_wb to the
                     new wikibox *)
                  >>= fun box ->
                  Lwt.return
                    (Some (Wiki_syntax.string_of_extension "wikibox"
                             (("box", Int32.to_string box)::args) c))
            | false -> Lwt.return None
   with Failure _ -> Lwt.return None)
  );

Wiki_syntax.add_extension ~name:"link" ~wiki_content:true
  (fun wiki_id bi args c ->
     Wikicreole.Link_plugin
       (let sp = bi.bi_sp in
        let href = Ocsimore_lib.list_assoc_default "page" args "" in
        let fragment = Ocsimore_lib.list_assoc_opt "fragment" args in
        let https = extract_https args in
        let wiki_id = extract_wiki_id args wiki_id in
        let content =
          match c with
            | Some c -> Wiki_syntax.a_content_of_wiki wiki_id bi c
            | None -> Lwt.return (Ocamlduce.Utf8.make href)
        in
        (* class and id attributes will be taken by Wiki_syntax.a_elem *)
        ((if Wiki_syntax.is_absolute_link href then
            href
          else
            match Wiki_services.find_servpage wiki_id with
              | Some s ->
                  let href = Ocsigen_lib.remove_slash_at_beginning
                    (Neturl.split_path href)
                  in Eliom_duce.Xhtml.make_uri
                       ?https ?fragment ~service:s ~sp href
              | None -> href
         ),
         args,
         content)
       )
  );

Wiki_syntax.add_extension ~name:"nonattachedlink" ~wiki_content:true
  (fun wiki_id bi args c ->
     Wikicreole.Link_plugin
       (let sp = bi.bi_sp in
        let href = Ocsimore_lib.list_assoc_default "page" args "" in
        let fragment = Ocsimore_lib.list_assoc_opt "fragment" args in
        let https = extract_https args in
        let wiki_id = extract_wiki_id args wiki_id in
        let content =
          match c with
            | Some c -> Wiki_syntax.a_content_of_wiki wiki_id bi c
            | None -> Lwt.return (Ocamlduce.Utf8.make href)
        in
        (Eliom_duce.Xhtml.make_uri ?https ?fragment
           ~service:(Wiki_services.find_naservpage wiki_id) ~sp href,
         args,
         content)
       )
  );

Wiki_syntax.add_extension ~name:"cancellink" ~wiki_content:true
  (fun wiki_id bi args c ->
     Wikicreole.Link_plugin
       (let content =
          match c with
            | Some c -> Wiki_syntax.a_content_of_wiki wiki_id bi c
            | None -> Lwt.return (Ocamlduce.Utf8.make "Cancel")
        in
        (Eliom_duce.Xhtml.make_uri ~service:Eliom_services.void_coservice'
           ~sp:bi.bi_sp (),
         args,
         content)
       )
  );


Wiki_syntax.add_extension ~name:"object" ~wiki_content:true
  (fun wiki_id bi args _c ->
     Wikicreole.A_content
       (let type_ = Ocsimore_lib.list_assoc_default "type" args "" in
        let href = Ocsimore_lib.list_assoc_default "data" args "" in
        let fragment = Ocsimore_lib.list_assoc_opt "fragment" args in
        let wiki_id = extract_wiki_id args wiki_id in
        let https = extract_https args in
        let atts = Wiki_syntax.parse_common_attribs args in
        let url =
          if Wiki_syntax.is_absolute_link href then
            href
          else
            match Wiki_services.find_servpage wiki_id with
              | Some s ->
                  let href = Ocsigen_lib.remove_slash_at_beginning
                    (Neturl.split_path href)
                  in
                  Eliom_duce.Xhtml.make_uri ?https ?fragment ~service:s
                    ~sp:bi.bi_sp href
              | None -> href
        in
        Lwt.return
          {{ [<object
                 ({data = {: Ocamlduce.Utf8.make url :}
                   type = {: Ocamlduce.Utf8.make type_ :}}
                  ++ atts)>[] ] }})
  );

Wiki_syntax.add_extension ~name:"img" ~wiki_content:true
  (fun wiki_id bi args c ->
     Wikicreole.A_content
       (let href = Ocsimore_lib.list_assoc_default "name" args "" in
        let https = extract_https args in
        let wiki_id = extract_wiki_id args wiki_id in
        let alt = match c with Some c -> c | None -> href in
        let atts = Wiki_syntax.parse_common_attribs args in
        let url =
          if Wiki_syntax.is_absolute_link href then
            href
          else
            match Wiki_services.find_servpage wiki_id with
              | Some s ->
                  let href =
                    Ocsigen_lib.remove_slash_at_beginning
                      (Neturl.split_path href)
                  in
                  Eliom_duce.Xhtml.make_uri ?https ~service:s
                    ~sp:bi.bi_sp href
              | _ -> href
        in
        Lwt.return
          {{ [<img ({ src={: Ocamlduce.Utf8.make url :}
                        alt={: Ocamlduce.Utf8.make alt :}}
                    ++ atts )>[] ] }})
  );
 
