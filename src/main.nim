import asynchttpserver, asyncdispatch
import strutils, uri, tables, json, options, strformat
import database
import db_connector/db_sqlite
import nimja/parser
import std/hashes, checksums/sha1
import times, locks
import os, random

type
  User = object
    id: int64
    email: string
    password_hash: string
    name: string
    color: string
    created_at: Date_time

  MileEntry = object
    id: int64
    user_id: int64
    miles: float
    logged_at: Date_time

  Session = object
    user_id: int64
    email: string

const
  static_dir = "static"
  port = 8080

var sessions: Table[string, Session]
var sessions_lock: Lock
var db_conn: DbConn

proc hash_password(password: string): string =
  return $secureHash(password)

proc verify_password(password, hash: string): bool =
  return $secureHash(password) == hash

proc generate_session_id(): string =
  let now = $epoch_time()
  return $hash(now & "salt")

proc get_user_from_session(session_id: string): Option[Session] =
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

proc render_template(template_name: string, context: JsonNode = newJObject(), session: Option[Session] = none(Session)): string {.gcsafe.} =
  var template_context = context
  if template_context.isNil:
    template_context = newJObject()
  
  # Add session info to context
  if session.is_some:
    template_context["session"] = newJBool(true)
  else:
    template_context["session"] = newJBool(false)
  
  # Use nimja to render templates from files
  return compile_template_file(path = & template_name, base_dir = get_script_dir(), context = template_context)

proc handle_request(req: Request) {.async, gcsafe.} =
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
        response_body = render_template("index.ninja", newJObject(), session)
      of "/login":
        response_body = render_template("login.ninja", newJObject(), session)
      of "/signup":
        response_body = render_template("signup.ninja", newJObject(), session)
      of "/leaderboard":
        let leaderboard = get_leaderboard(db_conn)
        var json_leaderboard = newJArray()
        
        for entry in leaderboard:
          var user_obj = newJObject()
          user_obj["name"] = newJString(entry.user.name)
          user_obj["color"] = newJString(entry.user.color)
          
          var entry_obj = newJObject()
          entry_obj["user"] = user_obj
          entry_obj["total_miles"] = newJFloat(entry.total_miles)
          entry_obj["last_miles"] = if entry.last_miles.is_some: newJFloat(entry.last_miles.get()) else: newJNull()
          entry_obj["streak"] = newJInt(entry.streak)
          
          json_leaderboard.add(entry_obj)
        
        var context = newJObject()
        context["leaderboard"] = json_leaderboard
        response_body = render_template("leaderboard.ninja", context, session)
      
      of "/log":
        if session.is_none:
          status = Http302
          headers = new_http_headers([("Location", "/login")])
        else:
          response_body = render_template("log.ninja", newJObject(), session)
      
      of "/about":
        response_body = render_template("about.ninja", newJObject(), session)
      
      of "/settings":
        if session.is_none:
          status = Http302
          headers = new_http_headers([("Location", "/login")])
        else:
          let user_opt = get_user_by_email(db_conn, session.get().email)
          if user_opt.is_some:
            let user = user_opt.get()
            var context = newJObject()
            var user_data = newJObject()
            user_data["name"] = newJString(user.name)
            user_data["email"] = newJString(user.email)
            user_data["color"] = newJString(user.color)
            context["user"] = user_data
            response_body = render_template("settings.ninja", context, session)
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
        let passkey = form_data.getOrDefault("passkey", "")
        let name = form_data.getOrDefault("name", "")
        let email = form_data.getOrDefault("email", "")
        let password = form_data.getOrDefault("password", "")
        let color = form_data.getOrDefault("color", "#3b82f6")
        
        if passkey == "":
          response_body = """<p style="color: red;">Passkey is required</p>"""
        elif name == "":
          response_body = """<p style="color: red;">Name is required</p>"""
        elif email == "":
          response_body = """<p style="color: red;">Email is required</p>"""
        elif password == "":
          response_body = """<p style="color: red;">Password is required</p>"""
        elif not validate_passkey(db_conn, passkey):
          response_body = """<p style="color: red;">Invalid or already used passkey</p>"""
        elif get_user_by_email(db_conn, email).is_some:
          response_body = """<p style="color: red;">Email already registered</p>"""
        else:
          try:
            let password_hash = hash_password(password)
            let user_id = create_user(db_conn, email, password_hash, name, color)
            use_passkey(db_conn, passkey)
            
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
          let miles_str = form_data.getOrDefault("miles", "")
          try:
            let miles = parseFloat(miles_str)
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
          let name = form_data.getOrDefault("name", "")
          let color = form_data.getOrDefault("color", "#3b82f6")
          let current_password = form_data.getOrDefault("current_password", "")
          let new_password = form_data.getOrDefault("new_password", "")
          let confirm_password = form_data.getOrDefault("confirm_password", "")
          
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
