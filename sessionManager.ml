open XHTML.M
open Eliom
open Eliom.Xhtml
open Lwt
open Users

let user_table : Users.user persistent_table = 
  create_persistent_table "ocsimore_user_table_v1"

type sessionmanager_in = 
    { url: string list;
      default_groups: Users.user list;
      login_actions: Eliom.server_params -> Users.user option -> unit;
      logout_actions: Eliom.server_params -> unit;
      registration_mail_from: string * string;
      registration_mail_subject: string;
  }

class type sessionmanager = object
  method mk_log_form: Eliom.server_params -> Users.user option -> 
    XHTML.M.block XHTML.M.elt
end

class makesessionmanager
    (sessionmanagerinfo: sessionmanager_in) 
    ~(exit_link : Eliom.server_params -> Xhtmltypes.p_content XHTML.M.elt) = 

  let act_login = new_post_coservice'
    ~post_params:(string "usr" ** string "pwd")
    ()
  in

  let act_logout = new_post_coservice'
    ~post_params:unit
    ()
  in

  let srv_register = new_service 
    ~url:(sessionmanagerinfo.url @ ["register"])
    ~get_params:unit
    ()
  in

  let srv_register_done = new_post_coservice
    ~fallback:srv_register
    ~post_params:(string "usr" ** (string "descr" ** string "email"))
    ()
  in

  let srv_reminder = new_service
    ~url:(sessionmanagerinfo.url @ ["reminder"])
    ~get_params:unit
    ()
  in

  let srv_reminder_done = new_post_coservice
    ~fallback:srv_register
    ~post_params:(string "usr")
    ()
  in

  let srv_edit = new_coservice
      ~fallback:srv_register
      ~get_params:unit
      ()
  in

  let srv_edit_done = new_post_coservice
      ~fallback:srv_register
      ~post_params:(string "pwd" ** (string "pwd2" ** (string "descr" ** 
						         string "email")))
      ()
  in


  let valid_username usr =
    Str.string_match (Str.regexp "^[A-Za-z0-9]+$") usr 0
  in

  let valid_emailaddr email =
    Str.string_match 
      (Str.regexp ("^[A-Za-z0-9\\._-]+@" 
		   ^ "\\([A-Za-z0-9][A-Za-z0-9_-]+\\.\\)+\\([a-z]+\\)+$")) 
      email 0
  in

  let login_box sp error usr pwd = 
    [table
       (tr(td [pcdata "Username:"]) 
	  [td [string_input usr]])
       ([tr(td [pcdata "Password:"]) 
	   [td [string_password_input pwd]];
	 tr(td [submit_input "login"]) 
	   [];
	 tr(td ~a:[a_colspan 2] 
	      [a srv_register sp [pcdata "New user? Register now!"] ()]) 
	   []]
	@ (if error
	   then [tr(td ~a:[a_colspan 2]
		      [a srv_reminder sp [pcdata "Forgot your password?"] ()])
		   []]
	   else []))]
  in
  
  let logout_box sp user =
    let (usr,pwd,descr,email) = get_user_data user in
    [table
       (tr(td [pcdata ("Hi " ^ descr ^ "!")]) [])
       [tr(td [submit_input "logout"]) [];
	tr(td [a srv_edit sp [pcdata "Manage your account"] ()]) []]]
  in
      
  let page_register err = fun sp () ()-> 
    return 
      (html
	 (head (title (pcdata "Registration")) [])
	 (body [h1 [pcdata "Registration form"];
		p [pcdata "Please fill in the following fields.";
		   br();
		   pcdata "You can freely choose your login name: it will be \
                           slightly modified automatically whether it had \
                           been already chosen by another registered user.";
		   br();
		   pcdata "Be very careful to enter a valid e-mail address, \
                           as the password for logging in will be sent \
                           there."];
		post_form 
		  srv_register_done 
		  sp
		  (fun (usr,(desc,email)) -> 
		     [table
			(tr(td [pcdata "login name: (letters & digits only)"])
			   [td [string_input usr]])
			[tr(td [pcdata "enter your name:"])
			   [td [string_input desc]];
			 tr(td [pcdata "your e-mail address:"])
			   [td [string_input email]];
			 tr(td [submit_input "Register"])
			   []]])
		  ();
		p [strong [pcdata err]]]))
  in

  let page_register_done = fun sp () (usr,(desc,email))-> 
    if not (valid_username usr) then 
      page_register "ERROR: Bad character(s) in login name!" sp () ()
    else if not (valid_emailaddr email) then 
      page_register "ERROR: Bad formed e-mail address!" sp () ()
    else 
      let pwd = generate_password() in
      let (user,n) = create_unique_user ~name:usr ~pwd ~desc ~email in
	if (mail_password 
	      ~name:n ~from_addr:sessionmanagerinfo.registration_mail_from 
	      ~subject:sessionmanagerinfo.registration_mail_subject) 
	then 
	  return 
	    (ignore (List.map 
		       (fun g-> add_group ~user ~group:g) 
		       sessionmanagerinfo.default_groups);
	     html
	       (head (title (pcdata "Registration")) [])
	       (body [h1 [pcdata "Registration ok."];
		      p [pcdata "You'll receive soon an e-mail message at the \
                                 following address:";
			 br();
			 pcdata email;
			 br();
			 pcdata "reporting your login name and password."];
		      p [exit_link sp]]))
	else 
	  return 
	    (delete_user ~user;
	     html
	       (head (title (pcdata "Registration")) [])
	       (body [h1 [pcdata "Registration failed."];
		      p [pcdata "Please try later."];
		      p [exit_link sp]]))
  in

  let page_reminder err = fun sp () () -> 
    return 
      (html
	 (head (title (pcdata "Password reminder")) [])
	 (body [h1 [pcdata "Password reminder"];
		p [pcdata "This service allows you to get an e-mail message \
                           with your connection password.";
		   br();
		   pcdata "The message will be sent to the address you \
                           entered when you registered your account."];
		post_form 
		  srv_reminder_done 
		  sp
		  (fun usr -> 
		     [table
			(tr(td [pcdata "Enter your login name:"])
			   [td [string_input usr];
			    td [submit_input "Submit"]])
			[]])
		  ();
		p [strong [pcdata err]]]))
  in

  let page_reminder_done = fun sp () usr ->
    if not (valid_username usr) then
      page_reminder "ERROR: Bad character(s) in login name!" sp () ()
    else (if (mail_password 
		~name:usr ~from_addr:sessionmanagerinfo.registration_mail_from 
		~subject:sessionmanagerinfo.registration_mail_subject) 
	  then 
	    return 
	      (html
		 (head (title (pcdata "Password reminder")) [])
		 (body [h1 [pcdata "Password sent."];
			p [pcdata "You'll receive soon an e-mail message at \
                                   the address you entered when you \
                                   registered your account."];
			p [exit_link sp]]))
	  else 
	    return 
	      (html
		 (head (title (pcdata "Password reminder")) [])
		 (body [h1 [pcdata "Failure."];
			p [pcdata "The username you entered doesn't exist, or \
                                   the service is unavailable at the moment."];
			p [exit_link sp]])))
  in

  let page_edit user err = fun sp () () ->
    let (n,_,d,e) = get_user_data ~user in
      return 
	(html
	   (head (title (pcdata "Your account")) [])
	   (body [h1 [pcdata "Your account"];
		  p [pcdata "Change your personal information:"];
		  post_form 
		    srv_edit_done 
		    sp
		    (fun (pwd,(pwd2,(desc,email))) -> 
		       [table 
			  (tr(td [pcdata "login name: "])
			     [td [strong [pcdata n]]])
			  [tr(td [pcdata "real name:"])
			     [td [string_input ~value:d desc]];
			   tr(td [pcdata "e-mail address:"])
			     [td [string_input ~value:e email]];
			   tr(td ~a:[a_colspan 2]
				[pcdata "enter a new password twice, or \
                                         leave blank for no changes:"])
			     [];
			   tr(td [string_password_input ~value:"" pwd])
			     [td [string_password_input ~value:"" pwd2]];
			   tr(td [submit_input "Confirm"])
			     []]]) 
		    ();
		  p [strong [pcdata err]]]))
  in

  let page_edit_done user = fun sp () (pwd,(pwd2,(desc,email)))->
    if not (valid_emailaddr email) then 
      page_edit user "ERROR: Bad formed e-mail address!" sp () ()
    else if pwd <> pwd2 then
      page_edit user "ERROR: Passwords don't match!" sp () ()
    else
      return
	(ignore (if pwd = ""
		 then update_user_data ~user ~desc ~email ()
		 else update_user_data ~user ~desc ~email ~pwd:(Some pwd) ());
	 html
	   (head (title (pcdata "Your account")) [])
	   (body [h1 [pcdata "Personal information updated."];
		  p [exit_link sp]]))
  in

  let mk_act_login sp () (usr,pwd) = 
    sessionmanagerinfo.logout_actions sp; 
    close_session sp >>= 
    (fun () -> 
      catch
        (fun () ->
          authenticate usr pwd >>= 
          (fun user -> 
            set_persistent_data user_table sp user >>=
            (fun () ->
              return (
              sessionmanagerinfo.login_actions sp (Some user);
              register_for_session sp srv_edit (page_edit user "");
              register_for_session sp srv_edit_done (page_edit_done user);
              []
             ))))
        (fun e -> return [e]))
  in

	
  let mk_act_logout sp () () = 
    sessionmanagerinfo.logout_actions sp; 
    close_session sp >>= (fun () -> return [])
  in

  object

    method mk_log_form : Eliom.server_params -> Users.user option -> 
      XHTML.M.block XHTML.M.elt
        = fun sp sess -> match sess with
          | Some user -> (* user is logged in *)
              post_form ~a:[a_class ["logbox";"logged"]] 
	        act_logout sp (fun _ -> logout_box sp user) ()
          | _ ->
              let exn = get_exn sp in
              if List.mem BadPassword exn || List.mem NoSuchUser exn
              then (* unsuccessful attempt *)
	        post_form ~a:[a_class ["logbox";"error"]] 
	          act_login sp (fun (usr, pwd) -> 
                    (login_box sp true usr pwd)) ()
              else (* no login attempt yet *)
	        post_form ~a:[a_class ["logbox";"notlogged"]] 
	          act_login sp (fun (usr, pwd) -> 
                    (login_box sp false usr pwd)) ()

    initializer
      Actions.register act_login mk_act_login;
      Actions.register act_logout mk_act_logout;
      register srv_register (page_register "");
      register srv_register_done page_register_done;
      register srv_reminder (page_reminder "");
      register srv_reminder_done page_reminder_done;

  end
