open Lwt
open Eliommod
open Eliomparameters
open Eliomservices
open Eliomsessions
open Eliomduce.Xhtml
open SessionManager
open Ocsimorelib
open Widget

type message_data =
{
	id: int;
	text: string;
	author: string;
	datetime: Calendar.t
};;

class login_widget ~(parent: sessionmanager) =
object (self)
	inherit [unit] parametrized_widget parent

	val div_class = "logbox"

  method private login_box sp error usr pwd =
  {{ [<table>([
      <tr>[<td>"Username:" <td>[{: string_input ~input_type:{:"text":} ~name:usr () :}]]
      <tr>[<td>"Password:" <td>[{: string_input ~input_type:{:"password":} ~name:pwd () :}]]
      <tr>[<td>[{: string_input ~input_type:{:"submit":} ~value:"Login" () :}]]
      <tr>[<td colspan="2">[{: a parent#srv_register sp {{ "New user? Register now!" }} () :}]]] @
      {: if error then
        {{ [<tr>[<td colspan="2">"Wrong login or password"]
        <tr>[<td colspan="2">[{: a parent#srv_reminder sp {{ "Forgot your password?" }} () :}]]] }}
        else
       {{ [] }} :})] }}

  method private logout_box sp user =
  let (usr,pwd,descr,email) = parent#get_user_data in
  {{ [<table>[
      <tr>[<td>{: Printf.sprintf "Hi %s!" descr :}]
      <tr>[<td>[{: string_input ~input_type:{:"submit":} ~value:"logout" () :}]]
      <tr>[<td>[{: a parent#srv_edit sp {{ "Manage your account" }} () :}]]
  ]] }}

	method apply ~sp () =
	get_persistent_session_data SessionManager.user_table sp () >>=
	fun sess -> return {{ <div class={: div_class :}>[{:
		match sess with
		| Data user ->
			post_form ~a:{{ { class="logbox logged"} }} ~service:parent#act_logout ~sp
				(fun _ -> self#logout_box sp user) ()
		| _ ->  let exn = get_exn sp in
              if List.mem Users.BadPassword exn || List.mem Users.NoSuchUser exn
              then (* unsuccessful attempt *)
          post_form ~a:{{ {class="logbox error"} }}
            ~service:parent#act_login ~sp:sp (fun (usr, pwd) ->
                    (self#login_box sp true usr pwd)) ()
              else (* no login attempt yet *)
          post_form ~a:{{ {class="logbox notlogged"} }}
            ~service:parent#act_login ~sp:sp (fun (usr, pwd) ->
                    (self#login_box sp false usr pwd)) () :}] }}

end;;

class message_widget ~(parent: sessionmanager) =
object (self)
	inherit [int] parametrized_widget parent

	val div_class = "message"
	val mutable subject = ""
	val mutable author = ""
	val mutable text = ""
	val mutable datetime = Calendar.now ()
	val mutable hidden = false
	val mutable sticky = false

	method set_subject s = subject <- s
	method set_author a = author <- a
	method set_text t = text <- t
	method set_datetime d = datetime <- d
	method set_hidden h = hidden <- h
	method set_sticky s = sticky <- s

	method apply ~sp (message_id) =
	self#retrieve_data (message_id) >>=
	fun () -> return
	{{ <div class={: div_class :}>[
			<h4>{: Format.sprintf "posted by: %s %s" author (sod datetime) :}
			!{:
				(* XXX if forum#can_moderate sess || forum#can_write sess then *)
					{{ [<p>{: Format.sprintf "Hidden: %s; sticky: %s" (if hidden then "YES" else "NO") (if sticky then "YES" else "NO") :}] }}
				(* else
					{{ [] }} *)
			:}
			<pre>{: text :}
			(* TODO: reply to this message *)
	] }}
end;;

class message_list_widget ~(parent: sessionmanager) = 
object (self)
	inherit [message_data] list_widget parent
	inherit [int * int * int option * int option] parametrized_widget parent

	val div_class = "message_list"
	val db = Sql.connect ()

	method private retrieve_data (forum_id, thread_id, offset, limit) =
	let thr_id = Sql.db_int_of_int thread_id in
	db >>=
	fun db -> Sql.thread_get_messages_with_text db ~thr_id ~role:(parent#get_role forum_id) ?offset ?limit () >>=
	fun results ->
	Lwt_util.map
		(fun (i, t, a, d, _, _) ->
			return { id = (Sql.int_of_db_int i); text = t; author = a; datetime = d })
		results >>=
	fun children -> return (self#set_children children)
	
	method apply ~sp (forum_id, thread_id, offset, limit) =
	self#retrieve_data (forum_id, thread_id, offset, limit) >>=
	fun () -> return self#get_children >>=
	fun subjects -> Lwt_util.map (fun s -> return {{
		<div class="message_data">
		[
			<h4>['posted by: ' !{: s.author :} ' ' !{: sod s.datetime :}]
			<pre>{: s.text :}
		]
	}}) subjects >>=
	fun rows -> return
	{{
		<div class={: div_class :}>[
			!{:
				match rows with
				| [] -> {{ [<p>"This thread does not contain any messages."] }}
				| l -> {{ {: l :} }}
			:}
		]
	}}
end;;

class message_navigation_widget ~(parent: sessionmanager) ~(srv_thread:(int * (int * int option), unit, get_service_kind, [`WithoutSuffix], [`One of int] param_name * ([`One of int] param_name * [`Opt of int] param_name), unit, [`Registrable]) service) =
object (self)
	inherit [int * int * int option * int option] parametrized_widget parent

	val div_class = "message_navigation"
	val mutable nr_messages = 0
	val db = Sql.connect ()

	method private retrieve_data (forum_id, thread_id, offset, limit) =
	let thr_id = Sql.db_int_of_int thread_id in
	db >>=
	fun db -> Sql.thread_get_nr_messages db ~thr_id ~role:(parent#get_role forum_id) >>=
	fun nr_m -> nr_messages <- nr_m; Messages.debug2 "[message_navigation_widget] retrieve_data: end";
	return ()

	method apply ~sp (forum_id, thread_id, offset, limit) =
	Messages.debug2 "[message_navigation_widget] apply";
	self#retrieve_data (forum_id, thread_id, offset, limit) >>=
	fun () -> Messages.debug2 "[message_navigation_widget] apply: end"; return {{
		<div class={: div_class :}>
		{:
			match limit with
			|	None -> {{ [] }}
			| Some l -> {{
				[<table>[
					<tr>[
						<td>{: if offset = None || offset = Some 0 then
								{{ "First" }}
							else
								{{[{: a srv_thread sp {{"First"}} (forum_id, (thread_id, None)) :}]}}
							:}
						<td>{: match offset with
							| None -> {{ "Previous" }}
							| Some o -> if o <= l then
									{{[{: a srv_thread sp {{"Previous"}} (forum_id, (thread_id, None)) :}]}}
								else
									{{[{: a srv_thread sp {{"Previous"}} (forum_id, (thread_id, Some (o-l))) :}]}}
						:}
						<td>{: let o = match offset with None -> 0 | Some x -> x in
							if (o + l) >= nr_messages then
								{{ "Next" }}
							else
								{{[{: a srv_thread sp {{"Next"}} (forum_id, (thread_id, Some (o+l))):}]}}
						:}
						<td>{: let o = match offset with None -> 0 | Some x -> x in
							if l >= nr_messages || (o + l) >= nr_messages then
								{{ "Last" }}
							else
								{{[{: a srv_thread sp {{"Last"}} (forum_id, (thread_id, Some (nr_messages-nr_messages mod l))):}]}}
						:}
						]
				]]
			}}
		:}
	}}
end;;

class message_forest_widget ~(parent: sessionmanager) ~(srv_reply_message:(int * (int * (int option * int)), unit, get_service_kind, [`WithoutSuffix], [`One of int] param_name * ([`One of int] param_name * ([`Opt of int] param_name * [`One of int] param_name)), unit, [`Registrable]) service) =
object (self)
	inherit [int * int * int option] parametrized_widget parent

	val div_class = "message_forest"
	val mutable children: message_data tree list = []
	val db = Sql.connect () 

	method set_children c = children <- c

	method get_children = children

	method private retrieve_data (forum_id, thread_id, btm) =
	let thr_id = Sql.db_int_of_int thread_id
	and bottom = match btm with
	| None -> None
	| Some x -> Some (Sql.db_int_of_int x) in
	db >>=
	fun db -> Sql.thread_get_messages_with_text_forest db ~thr_id ~role:(parent#get_role forum_id) ?bottom () >>=
	fun results -> lwt_forest_map
		(fun (i, t, a, d, _, _, _, _) ->
			return { id = (Sql.int_of_db_int i); text = t; author = a; datetime = d })
		results >>=
	fun children -> return (self#set_children children)

	method apply ~sp (forum_id, thread_id, bottom) =
	let rec listize_forest (f: Xhtml1_strict._div tree list): Xhtml1_strict.ul list Lwt.t =
		Lwt_util.map (function 
		| Node (p, ch) -> listize_forest ch >>=
			fun rest -> return {{ <ul>[ 
				<li>[{: p :}]
				!{: List.map (fun r -> {{ <li>[{: r :}] }}) rest :}
			] }}) f
	in
	self#retrieve_data (forum_id, thread_id, bottom) >>=
	fun () -> return self#get_children >>=
	fun subjects -> lwt_forest_map (fun s -> return {{
		<div class="message_data">
		[
			<h4>['posted by: ' !{: s.author :} ' ' !{: sod s.datetime :}]
			<pre>{: s.text :}
			{: a srv_reply_message sp {{ "Reply to this message" }} (forum_id, (thread_id, (None, s.id))) :}
		]
	}}) subjects >>=
	fun forest -> listize_forest forest >>=
	fun div_contents -> return {{
		<div class={: div_class :}>{: div_contents :}
	}}
end;;

class message_form_widget ~(parent: sessionmanager) ~(srv_add_message: (int * (int * int option), string * (int option * bool), post_service_kind, [`WithoutSuffix], [`One of int] param_name * ([`One of int] param_name * [`Opt of int] param_name), [`One of string] param_name * ([`Opt of int] param_name * [`One of bool] param_name), [`Registrable]) service) =
object (self)
	inherit [int * int * int option * int option] parametrized_widget parent

	val div_class = "message_form"
	val mutable my_parent_id = None

	method private form (message, (parent_id, sticky)) =
	{: [
		<h2>{: 
			match my_parent_id with
			| None -> "Post a new message in this thread:"
			| Some _ -> "Reply to this message:" 
		:}
		!{: match my_parent_id with
			None -> {{ [] }}
		|	Some p -> {{ [<p>[ {: int_input ~input_type:{: "hidden" :} ~name:parent_id ~value:p () :}]] }} :}
		<p>[{: bool_checkbox ~name:sticky () :} ' Sticky message']
		<p>[{: textarea ~name:message ~rows:5 ~cols:80 ~value:{{ "Your message here" }} () :}]
		<p>[{: string_input ~input_type:{: "submit" :} ~value:"OK" () :}]
	] :}

	method apply ~(sp:server_params) (forum_id, thread_id, parent_id, offset) =
	Messages.debug2 "[message_form_widget] apply (& end)";
	my_parent_id <- parent_id;
	return {{
		<div class={: div_class :}>[
			{: (post_form ~service:srv_add_message ~sp self#form) (forum_id, (thread_id, offset)) :}
		] }}
end;;

class message_add_action ~(parent: sessionmanager) = 
object (self)
	inherit [int * int * int option * string * bool] parametrized_widget parent
	
	val div_class = "message_add`"
	val db = Sql.connect ()

	method apply ~sp (forum_id, thread_id, par_id, txt, sticky) =
	let thr_id = Sql.db_int_of_int thread_id
	and parent_id = 
		match par_id with
		| None -> None
		| Some x -> Some (Sql.db_int_of_int x)
	and author = parent#get_user_name in
		db >>=
		fun db -> Sql.new_message db ~thr_id ?parent_id ~author ~txt ~sticky () >>=
		fun _ -> return {{
		<div class={: div_class :}>[
			<p>"Your message has been added."
		]
	}}
end;;

class latest_messages_widget ~(parent: sessionmanager) =
object (self)
	inherit [int list * int] parametrized_widget parent

	val div_class = "latest_messages"
	val mutable messages = []
	val db = Sql.connect ()
	
	method private set_messages m = messages <- m

	method private retrieve_data (forum_ids, limit) =
	let frm_ids = List.map Sql.db_int_of_int forum_ids in
	db >>=
	fun db -> Sql.get_latest_messages db ~frm_ids ~limit () >>=
	fun res -> return (self#set_messages res)

	method apply ~sp (forum_ids, limit) =
	self#retrieve_data (forum_ids, limit) >>=
	fun () -> Lwt_util.map (fun (id, msg, author) ->
		return {{ <tr>[<td>{: msg :} <td>{: author :}] }} ) messages >>=
	fun tbl -> return {{
		<div class={: div_class :}>{:
			match tbl with
			| [] -> {{ [<p>"There are no messages for the moment."] }}
			| l -> {{ [<table>[
				<tr>[<th>"Message" <th>"Author"]
				!{: l :}
			]] }}
		:}
	}}
end;;

type thread_data =
{
	id: int;
	subject: string;
	author: string;
	datetime: Calendar.t
};;

class thread_widget ~(parent: sessionmanager) =
object (self)
	inherit [int * int] parametrized_widget parent

	val div_class = "thread"
	val mutable subject = ""
	val mutable author = ""
	val mutable article = None
	val mutable datetime = Calendar.now ()
	val mutable hidden = false
	val mutable shown_messages = 0
	val mutable hidden_messages = 0
	val db = Sql.connect ()

	method set_subject s = subject <- s
	method set_author a = author <- a
	method set_article a = article <- (Some a)
	method set_datetime d = datetime <- d
	method set_hidden h = hidden <- h
	method set_shown_messages sm = shown_messages <- sm
	method set_hidden_messages hm = hidden_messages <- hm

	method get_subject = subject
	method get_author = author
	method get_article = article
	method get_datetime = datetime
	method get_hidden = hidden
	method get_shown_messages = shown_messages
	method get_hidden_messages = hidden_messages

	method private retrieve_data (forum_id, thread_id) =
	let thr_id = Sql.db_int_of_int thread_id in
	db >>=
	fun db -> Sql.thread_get_data db ~thr_id ~role:(parent#get_role forum_id) >>=
	fun (i, s, a, ar, d, h, sm, hm) ->
		self#set_subject s;
		self#set_author a;
		(match ar with
		| None -> ()
		| Some x -> self#set_article x);
		self#set_datetime d;
		self#set_hidden h;
		self#set_shown_messages sm;
		return (self#set_hidden_messages hm)

	method apply ~sp thread_id =
	Messages.debug2 "[thread_widget] apply";
	self#retrieve_data thread_id >>=
	fun () -> Messages.debug2 "[thread_widget] apply: end"; return
	{{ <div class={: div_class :}>[
		<h1>{: self#get_subject :}
		<h2>{: Printf.sprintf "Created by: %s %s" self#get_author (sod self#get_datetime) :}
		<div class="article">{:
			match self#get_article with
			| None -> {{ [] }}
			| Some a -> {{ [<pre>{: a :}] }}
		:}
	] }}
end;;

class thread_list_widget ~(parent: sessionmanager) ~(srv_thread:(int * (int * int option), unit, get_service_kind, [`WithoutSuffix], [`One of int] param_name * ([`One of int] param_name * [`Opt of int] param_name), unit, [`Registrable]) service) =
object (self)
	inherit [int] parametrized_widget parent
	inherit [thread_data] list_widget parent

	val div_class = "thread_list"
	val db = Sql.connect ()

	method private retrieve_data (forum_id) =
	Messages.debug2 (Printf.sprintf "[thread_list] retrieve_data (id: %d)"  forum_id);
	let frm_id = Sql.db_int_of_int forum_id in
	db >>=
	fun db -> Sql.forum_get_threads_list db ~frm_id ~role:(parent#get_role forum_id) () >>=
	fun result -> Lwt_util.map (fun (i, s, a, d, _) ->
		return { id = Sql.int_of_db_int i; subject = s; author = a; datetime = d }
	) result >>=
	fun children -> return (self#set_children children)

	method apply ~sp (forum_id) =
	catch (fun () -> self#retrieve_data forum_id >>=
	fun () -> return self#get_children >>=
	fun subjects ->  Messages.debug2 (Printf.sprintf "[thread_list] apply: %d items" (List.length subjects));
	Lwt_util.map (fun s -> return {{ <tr>[
			<td>{: sod s.datetime :}
			<td>[{: a ~service:srv_thread ~sp {{ {: s.subject :} }} (forum_id, (s.id, None)) :}]
			<td>{: s.author:}
		] }}) subjects >>=
	fun rows -> return {{
		<div class={: div_class :}>{:
			match rows with
			| [] -> {{ [<p>"This forum does not contain any threads."] }}
			| l -> {{ [<table>[
				<tr>[<th>"Time" <th>"Subject" <th>"Author"]
				!{: l :}
			]] }}
		:} }}) 
	(function 
	 Not_found -> return {{ <div class={: div_class :}>[<p>"This forum is not available."] }}
	| e -> return {{ <div class={: div_class :}>[
		<p>{: Printf.sprintf "Error: %s" (Printexc.to_string e) :}
	] }})
end;;

class thread_form_widget ~(parent: sessionmanager) ~(srv_add_thread: (int, bool * (string * string), post_service_kind, [`WithoutSuffix], [`One of int] param_name, [`One of bool] param_name * ([`One of string] param_name * [`One of string] param_name), [`Registrable]) service) =
object (self)
	inherit [int] parametrized_widget parent

	val div_class = "thread_form"

	method private form (is_article, (subject, txt)) =
	{{ [
		<h2>"Start a new thread"
		<table>[
			<tr>[<td>[{: bool_checkbox ~checked:true ~name:is_article () :} ' This message is an article']]
			<tr>[<td>['Subject: ' {: string_input ~input_type:{: "text" :} ~name:subject () :}]]
			<tr>[<td>[{: textarea ~name:txt ~rows:5 ~cols:80 ~value:{{ "Your message here" }} () :}]]
			<tr>[<td>[{: string_input ~input_type:{: "submit" :} ~value:"Submit" () :}]]
		]
	] }}

	method apply ~sp forum_id =
	return {{
		<div class={: div_class :}>[
			{: (post_form ~service:srv_add_thread ~sp self#form) forum_id :}
		] }}
end;;

class thread_add_action ~(parent: sessionmanager) =
object (self)
	inherit [int * bool * string * string] parametrized_widget parent
	
	val div_class = "thread_add"
	val db = Sql.connect ()

	method apply ~sp (forum_id, is_article, subject, txt) =
	let frm_id = Sql.db_int_of_int forum_id
	and author = parent#get_user_name in
	db >>=
	fun db -> (if is_article then
		Sql.new_thread_and_article db ~frm_id ~author ~subject ~txt
	else
		Sql.new_thread_and_message db ~frm_id ~author ~subject ~txt) >>=
	fun _ -> return {{
		<div class={: div_class :}>[
			<p>"The new thread has been created."
		]
	}}
end;;

type forum_data =
{
	id: int;
	name: string;
	description: string;
	moderated: bool;
};;

class forums_list_widget ~(parent: sessionmanager) ~(srv_forum: (int, unit, get_service_kind, [`WithoutSuffix], [`One of int] param_name, unit, [`Registrable]) service) =
object (self)
	inherit [unit] parametrized_widget parent
	inherit [forum_data] list_widget parent

  val div_class = "forums_list"
	val db = Sql.connect ()

	method private retrieve_data () =
	Messages.debug2 "[forums_list] retrieve_data";
	db >>=
	fun db -> Sql.get_forums_list db >>=
	fun result -> Lwt_util.map (fun (i, n, d, m) ->
		return { id = Sql.int_of_db_int i; name = n; description = d; moderated = m }
	) result >>=
	fun children -> return (self#set_children children)

	method apply ~sp () =
	self#retrieve_data () >>=
	fun () -> return self#get_children >>=
	fun subjects -> Lwt_util.map (fun s -> return {{ <tr>[
			<td>[{: a ~service:srv_forum ~sp {{ {: s.name :} }} s.id :}]
			<td>{: s.description :}
			<td>{: if s.moderated then "Yes" else "No" :}
		] }}) subjects >>=
	fun rows -> return {{
		<div class={: div_class :}>{:
			match rows with
			| [] -> {{ [<p>"There are no forums available."] }}
			| l -> {{ [<table>[
				<tr>[<th>"Name" <th>"Description" <th>"Moderated"]
				!{: l :}
			]] }}
		:}
	}}
end;;

class forum_form_widget ~(parent: sessionmanager) ~(srv_add_forum: (unit, bool * (string * string), post_service_kind, [`WithoutSuffix], unit, [`One of bool] param_name * ([`One of string] param_name * [`One of string] param_name), [`Registrable]) service) =
object (self)
	inherit [unit] parametrized_widget parent

	val div_class = "forum_form"

	method private form (is_moderated, (name, descr)) =
	{{ [
		<h2>"Start a new forum"
		<table>[
			<tr>[<td>[{: bool_checkbox ~checked:true ~name:is_moderated () :} ' This forum is moderated']]
			<tr>[<td>['Name: ' {: string_input ~input_type:{: "text" :} ~name:name () :}]]
			<tr>[<td>['Description: ' {: string_input ~input_type:{: "text" :} ~name:descr () :}]]
			<tr>[<td>[{: string_input ~input_type:{: "submit" :} ~value:"Submit" () :}]]
		]
	] }}

	method apply ~sp forum_id =
	return {{
		<div class={: div_class :}>[
			{: (post_form ~service:srv_add_forum ~sp self#form) () :}
		] }}
end;;

class forum_add_action ~(parent: sessionmanager) =
object (self)
	inherit [bool * string * string] parametrized_widget parent
	
	val div_class = "forum_add"
	val db = Sql.connect ()

	method apply ~sp (moderated, name, descr) =
	db >>=
	fun db -> 
		Sql.new_forum db ~title:name ~descr ~moderated >>=
	fun _ -> 
		return {{
		<div class={: div_class :}>[
			<p>"The new thread has been created."
		]
	}}
end;;
