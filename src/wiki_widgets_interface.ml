open Wiki_types
open Tyxml

type box_info = {
  bi_page: Document.t;
  bi_sectioning: bool;
  bi_add_link: Document.t -> unit;
  bi_content: Html_types.flow5 Html.elt list Lwt.t;
  bi_title: string;
}
