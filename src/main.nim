import asynchttpserver, asyncdispatch
import strutils, uri, tables, json, options, strformat
import database
import db_connector/db_sqlite
import nimja/parser
import std/hashes, checksums/sha1
from times import DateTime, epochTime
import locks
import os, random

type
  Session = object
    user_id: int64
    email: string

  User_Info = object
    name: string
    color: string
    initials: string

  User_Info_2 = object
    name: string
    email: string
    color: string
    initials: string

  Entry = object
    user: User_Info
    total_miles: float
    last_miles: float
    last_logged: string
    current_streak: int


const
  static_dir = "static"
  port = 8080

var sessions_lock: Lock
var sessions: Table[string, Session]
var db_conn: DbConn

proc get_initials(name: string): string =
  var initials = ""
  let parts = name.split()
  for part in parts:
    if part.len > 0:
      initials.add(part[0].toUpperAscii())
      if initials.len >= 2:
        break
  return if initials.len > 0: initials else: "??"

proc hash_password(password: string): string =
  return $secureHash(password)

proc verify_password(password, hash: string): bool =
  return $secureHash(password) == hash

proc generate_session_id(): string =
  let now = $epochTime()
  return $hash(now & "salt")

proc get_user_from_session(session_id: string): Option[Session] {.gcsafe.} =
  {.cast(gcsafe).}:
    with_lock sessions_lock:
      if session_id in sessions:
        return some(sessions[session_id])
      return none(Session)

proc parse_form_data(body: string): Table[string, string] =
  result = init_table[string, string]()
  if body.len == 0:
    return
  
  for pair in body.split("&"):
    let parts = pair.split("=", 1)
    if parts.len == 2:
      let key = parts[0].decode_url()
      let value = parts[1].decode_url()
      result[key] = value

proc render_template(template_name: static string, session: Option[Session] = none(Session), error_message: Option[string] = none(string), success_message: Option[string] = none(string), email: Option[string] = none(string), name: Option[string] = none(string), current_color: Option[string] = none(string), passkey: Option[string] = none(string), miles: Option[string] = none(string), current_total: Option[float] = none(float), user_id: Option[int64] = none(int64)): string {.gcsafe.} =
  compile_template_file(template_name, baseDir = get_script_dir())

proc render_leaderboard(user_stats: seq[Entry], session: Option[Session] = none(Session)): string {.gcsafe.} =
  compile_template_file("leaderboard.nimja", baseDir = get_script_dir())

proc render_settings(user: Option[User_Info_2], session: Option[Session] = none(Session), error_message: Option[string] = none(string), success_message: Option[string] = none(string), current_color: Option[string] = none(string), email: Option[string] = none(string)): string {.gcsafe.} =
  compile_template_file("settings.nimja", baseDir = get_script_dir())

proc handle_request(req: Request) {.async, gcsafe.} =
  {.cast(gcsafe).}:
    try:
      let url_parts = req.url.path.split('/')
      var response_body = ""
      var status = Http200
      var headers = new_http_headers([("Content-Type", "text/html")])
      
      # Get session
      var session: Option[Session] = none(Session)
      if req.headers.has_key("Cookie"):
        let cookies = req.headers["Cookie"]
        for cookie in cookies.split(";"):
          let parts = cookie.strip().split("=")
          if parts.len == 2 and parts[0] == "session_id":
            session = get_user_from_session(parts[1])
      
      case req.req_method:
      of Http_get:
        case req.url.path:
        of "/":
          response_body = render_template("index.nimja", session)
        of "/login":
          response_body = render_template("login.nimja", session)
        of "/signup":
          response_body = render_template("signup.nimja", session)
        of "/leaderboard":
          let leaderboard = get_leaderboard(db_conn)
          var user_stats: seq[Entry] = @[]
          for db_entry in leaderboard:
            var user: User_Info = User_Info(name: db_entry.user.name, color: db_entry.user.color, initials: get_initials(db_entry.user.name))
            let last_miles = if db_entry.last_miles.isSome: db_entry.last_miles.get() else: 0.0
            let last_logged = if db_entry.last_logged.isSome: $db_entry.last_logged.get() else: ""
            var entry: Entry = Entry(
              user: user, 
              total_miles: db_entry.total_miles, 
              last_miles: last_miles,
              last_logged: last_logged,
              current_streak: db_entry.streak
            )
            user_stats.add(entry)
          response_body = render_leaderboard(user_stats, session)
        
        of "/log":
          if session.is_none:
            status = Http302
            headers = new_http_headers([("Location", "/login")])
          else:
            let current_total = get_user_total_miles(db_conn, session.get().user_id)
            response_body = render_template("log_miles.nimja", session, none(string), none(string), none(string), none(string), none(string), none(string), none(string), some(current_total))
        
        of "/about":
          let user_id_opt = if session.isSome: some(session.get().user_id) else: none(int64)
          response_body = render_template("about.nimja", session, none(string), none(string), none(string), none(string), none(string), none(string), none(string), none(float), user_id_opt)
        
        of "/settings":
          if session.is_none:
            status = Http302
            headers = new_http_headers([("Location", "/login")])
          else:
            let user_opt = get_user_by_email(db_conn, session.get().email)
            if user_opt.is_some:
              let user = user_opt.get()
              var user_info: User_Info_2 = User_Info_2(name: user.name, email: user.email, color: user.color, initials: get_initials(user.name))
              response_body = render_settings(some(user_info), session, none(string), none(string), some(user.color), some(user.email))
            else:
              status = Http302
              headers = new_http_headers([("Location", "/login")])
        
        of "/logout":
          if session.is_some:
            # Remove session
            withLock sessions_lock:
              for sid, sess in sessions.pairs:
                if sess.user_id == session.get().user_id:
                  sessions.del(sid)
                  break
          status = Http302
          headers = new_http_headers([("Location", "/"), ("Set-Cookie", "session_id=; HttpOnly; Path=/; Max-Age=0")])
        else:
          status = Http404
          response_body = "Page not found"
          
      of Http_post:
        let content_length = if req.headers.has_key("content-length"): parse_int($req.headers["content-length"]) else: 0
        var body = ""
        if content_length > 0:
          body = req.body
        
        let form_data = parse_form_data(body)
        
        case req.url.path:
        of "/login":
          let email = form_data.get_or_default("email", "")
          let password = form_data.get_or_default("password", "")
          
          if email == "":
            response_body = """<p style="color: red;">Email is required</p>"""
          elif password == "":
            response_body = """<p style="color: red;">Password is required</p>"""
          else:
            let user_opt = get_user_by_email(db_conn, email)
            if user_opt.is_some and verify_password(password, user_opt.get().password_hash):
              let session_id = generate_session_id()
              withLock sessions_lock:
                sessions[session_id] = Session(user_id: user_opt.get().id, email: email)
              headers = new_http_headers([
                ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
                ("HX-Redirect", "/leaderboard")
              ])
              response_body = """<p style="color: green;">Login successful!</p>"""
            else:
              response_body = """<p style="color: red;">Invalid email or password</p>"""
        
        of "/signup":
          let passkey = form_data.get_or_default("passkey", "")
          if passkey == "":
            echo "Passkey is required"
          let name = form_data.get_or_default("name", "")
          let email = form_data.get_or_default("email", "")
          let password = form_data.get_or_default("password", "")
          let color = form_data.get_or_default("color", "#3b82f6")
          
          if passkey == "":
            response_body = """<p style="color: red;">Passkey is required</p>"""
          elif name == "":
            response_body = """<p style="color: red;">Name is required</p>"""
          elif email == "":
            response_body = """<p style="color: red;">Email is required</p>"""
          elif password == "":
            response_body = """<p style="color: red;">Password is required</p>"""
          elif not validate_passkey(db_conn, passkey):
            response_body = """<p style="color: red;">Invalid passkey</p>"""
          elif get_user_by_email(db_conn, email).is_some:
            response_body = """<p style="color: red;">Email already registered</p>"""
          else:
            try:
              let password_hash = hash_password(password)
              let user_id = create_user(db_conn, email, password_hash, name, color)
              
              let session_id = generate_session_id()
              with_lock sessions_lock:
                sessions[session_id] = Session(user_id: user_id, email: email)
              
              headers = new_http_headers([
                ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
                ("HX-Redirect", "/leaderboard")
              ])
              response_body = """<p style="color: green;">Account created successfully!</p>"""
            except:
              response_body = """<p style="color: red;">Error creating account</p>"""
        
        of "/log":
          if session.is_none:
            status = Http401
            response_body = """<p style="color: red;">You must be logged in to log miles</p>"""
          else:
            let miles_str = form_data.get_or_default("miles", "")
            try:
              let miles = parse_float(miles_str)
              if miles <= 0:
                response_body = """<p style="color: red;">Miles must be positive</p>"""
              elif miles > 50:
                response_body = """<p style="color: red;">Miles cannot exceed 50 per entry</p>"""
              else:
                log_miles(db_conn, session.get().user_id, miles)
                response_body = &"""<p style="color: green;">Logged {miles:.1f} miles successfully!</p>"""
            except:
              response_body = """<p style="color: red;">Invalid miles value</p>"""
        
        of "/settings":
          if session.is_none:
            status = Http401
            response_body = """<p style="color: red;">You must be logged in to update settings</p>"""
          else:
            let name = form_data.get_or_default("name", "")
            let color = form_data.get_or_default("color", "#3b82f6")
            let current_password = form_data.get_or_default("current_password", "")
            let new_password = form_data.get_or_default("new_password", "")
            let confirm_password = form_data.get_or_default("confirm_password", "")
            
            if name == "":
              response_body = """<p style="color: red;">Name is required</p>"""
            else:
              let user_opt = get_user_by_email(db_conn, session.get().email)
              if user_opt.is_none:
                response_body = """<p style="color: red;">User not found</p>"""
              else:
                let user = user_opt.get()
                var success = true
                var error_msg = ""
                
                # Update basic info
                try:
                  update_user(db_conn, user.id, name, color)
                except:
                  success = false
                  error_msg = "Error updating profile"
                
                # Handle password change if provided
                if current_password != "" or new_password != "" or confirm_password != "":
                  if current_password == "":
                    success = false
                    error_msg = "Current password is required"
                  elif new_password == "":
                    success = false
                    error_msg = "New password is required"
                  elif new_password != confirm_password:
                    success = false
                    error_msg = "New passwords don't match"
                  elif not verify_password(current_password, user.password_hash):
                    success = false
                    error_msg = "Current password is incorrect"
                  else:
                    try:
                      let new_hash = hash_password(new_password)
                      update_user_password(db_conn, user.id, new_hash)
                    except:
                      success = false
                      error_msg = "Error updating password"
                
                if success:
                  response_body = """<p style="color: green;">Settings updated successfully!</p>"""
                else:
                  response_body = &"""<p style="color: red;">{error_msg}</p>"""
        
        else:
          status = Http404
          response_body = "Endpoint not found"
      
      else:
        status = Http405
        response_body = "Method not allowed"
      
      
      await req.respond(status, response_body, headers)
    
    except Exception as e:
      echo "Error: ", e.msg
      await req.respond(Http500, "Internal server error")

proc main() {.async.} =
  echo "Initializing database..."
  db_conn = init_database()
  echo "Database initialized."
  
  init_lock(sessions_lock)
  
  var server = new_async_http_server()
  echo "Starting Winter 100 server on port ", port
  await server.serve(Port(port), handle_request)

when is_main_module:
  async_check main()
  run_forever()
