type t = {
  name: string;
  versions: Version.t list;
  latest: Version.t;
  manual_main: string option;
  default_subproject: string; (* "" when there aren't any *)
}


let (++) = Filename.concat

let is_directory path name =
  name.[0] <> '.' && name.[0] <> '_' && name.[0] <> '#' &&
  Sys.is_directory @@ path ++ name

let readdir wiki_dir path =
  let full = wiki_dir ++ path in
  Sys.readdir full |>
  Array.to_list |>
  List.filter (fun name -> is_directory full name)


let projects = ref []
let ids = ref []

let init wiki_dir =
  projects :=
    readdir wiki_dir "" |>
    List.map (fun name ->
      let versions =
        readdir wiki_dir name |>
        List.map Version.parse |>
        List.sort (fun x y -> Version.compare y x)
      in
      match versions with
      | [] ->
        Printf.eprintf "no versions found for %s...\n%!" name;
        []
      | Version.Dev :: latest :: _
      | latest :: _ ->
        let p =
          try
            let f =
              Yojson.Safe.from_file @@ wiki_dir ++ name ++ "config.js"
            in
            let default_subproject =
              Yojson.Safe.Util.member "default_subproject" f |>
              Yojson.Safe.Util.to_string_option |>
              Eliom_lib.Option.default_to ""
            in
            let manual_main =
              Yojson.Safe.Util.member "manual_main" f |>
              Yojson.Safe.Util.to_string_option
            in
            Yojson.Safe.Util.member "wiki_id" f |>
            Yojson.Safe.Util.to_int_option |> function
            | Some id ->
              ids := (id, name) :: !ids;
              {name; versions; latest; manual_main; default_subproject}
            | None ->
              {name; versions; latest; manual_main; default_subproject}
          with _ ->
            (* couldn't read config.js *)
            Printf.eprintf "couldn't read %s's config.js...\n%!" name;
            {name; versions; latest; manual_main=None; default_subproject=""}
        in
        [name, p]
    ) |>
    List.flatten

let get project =
  List.assoc project !projects

let of_id id =
  List.assoc id !ids
