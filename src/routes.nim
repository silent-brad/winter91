import asynchttpserver
import strutils, uri, tables, json, options, strformat
import database
import db_connector/db_sqlite
import locks
import os
from times import DateTime, epochTime, format
import types, auth, templates, utils

proc handle_get_routes*(req: Request, session: Option[Session], db_conn: DbConn): (string, HttpCode, HttpHeaders) =
  var response_body = ""
  var status = Http200
  var headers = new_http_headers([("Content-Type", "text/html")])
  
  case req.url.path:
  of "/":
    response_body = render_template("index.jinja", session)
  of "/login":
    response_body = render_template("login.jinja", session)
  of "/signup":
    response_body = render_template("signup.jinja", session)
  of "/leaderboard":
    if session.is_none:
      status = Http302
      headers = new_http_headers([("Location", "/login")])
    else:
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
        # Check for success parameter
        var success_msg: Option[string] = none(string)
        if req.url.query.len > 0:
          if "success=signup" in req.url.query:
            success_msg = some("Account created successfully! Welcome to Winter 100!")
          elif "success=login" in req.url.query:
            success_msg = some("Login successful! Welcome back to Winter 100!")
        
        response_body = render_leaderboard(user_stats, session, success_msg)

  of "/dashboard":
    if session.is_none:
      status = Http302
      headers = new_http_headers([("Location", "/login")])
    else:
      let current_total = get_user_total_miles(db_conn, session.get().user_id)
      # Check for success parameter
      var success_msg: Option[string] = none(string)
      if req.url.query.len > 0:
        if "success=signup" in req.url.query:
          success_msg = some("Account created successfully! Welcome to Winter 100!")
        elif "success=login" in req.url.query:
          success_msg = some("Login successful! Welcome back to Winter 100!")
      response_body = render_template("dashboard.jinja", session, none(string), success_msg, none(string), none(string), none(string), none(string), none(string), some(current_total))

  of "/log":
    if session.is_none:
      status = Http302
      headers = new_http_headers([("Location", "/login")])
    else:
      let current_total = get_user_total_miles(db_conn, session.get().user_id)
      response_body = render_template("dashboard.jinja", session, none(string), none(string), none(string), none(string), none(string), none(string), none(string), some(current_total))

  of "/about":
    let user_id_opt = if session.isSome: some(session.get().user_id) else: none(int64)
    response_body = render_template("about.jinja", session, none(string), none(string), none(string), none(string), none(string), none(string), none(string), none(float), user_id_opt)

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

  of "/api/user-miles-data":
    if session.is_none:
      status = Http401
      headers = new_http_headers([("Content-Type", "application/json")])
      response_body = "{\"error\": \"Unauthorized\"}"
    else:
      headers = new_http_headers([("Content-Type", "application/json")])
      let user_id = session.get().user_id
      let miles_by_date = get_user_miles_by_date(db_conn, user_id)
      let recent_entries = get_user_recent_entries(db_conn, user_id, 10)
      
      var dates_json = "["
      var miles_json = "["
      var entries_json = "["
      
      for i, entry in miles_by_date:
        if i > 0:
          dates_json.add(",")
          miles_json.add(",")
        dates_json.add("\"" & entry.date & "\"")
        miles_json.add($entry.miles)
      
      for i, entry in recent_entries:
        if i > 0:
          entries_json.add(",")
        let date_str = $entry.logged_at.format("yyyy-MM-dd")
        entries_json.add(&"""{{"date": "{date_str}", "miles": {entry.miles}}}""")
      
      dates_json.add("]")
      miles_json.add("]")
      entries_json.add("]")
      
      response_body = &"""{{"dates": {dates_json}, "miles": {miles_json}, "entries": {entries_json}}}"""

  of "/logout":
    if session.is_some:
      # Remove session
      with_lock sessions_lock:
        for sid, sess in sessions.pairs:
          if sess.user_id == session.get().user_id:
            sessions.del(sid)
            break
    status = Http302
    headers = new_http_headers([("Location", "/"), ("Set-Cookie", "session_id=; HttpOnly; Path=/; Max-Age=0")])
  else:
    # Check if it's a static file request
    if req.url.path.starts_with("/static/"):
      let file_path = req.url.path[1..^1]  # Remove leading slash
      let full_path = file_path
      if file_exists(full_path):
        let ext = split_file(full_path).ext.to_lower_ascii()
        let content_type = case ext:
          of ".js": "application/javascript"
          of ".css": "text/css"
          of ".html": "text/html"
          of ".png": "image/png"
          of ".jpg", ".jpeg": "image/jpeg"
          of ".gif": "image/gif"
          of ".svg": "image/svg+xml"
          of ".ico": "image/x-icon"
          else: "application/octet-stream"
        
        headers = new_http_headers([("Content-Type", content_type)])
        response_body = read_file(full_path)
      else:
        status = Http404
        response_body = "File not found"
    else:
      status = Http404
      response_body = "Page not found"
  
  return (response_body, status, headers)

proc handle_post_routes*(req: Request, session: Option[Session], db_conn: DbConn, PASSKEY: string): (string, HttpCode, HttpHeaders) =
  let content_length = if req.headers.has_key("content-length"): parse_int($req.headers["content-length"]) else: 0
  var body = ""
  if content_length > 0:
    body = req.body
  
  let form_data = parse_form_data(body)
  
  var response_body = ""
  var status = Http200
  var headers = new_http_headers([("Content-Type", "text/html")])
  
  case req.url.path:
  of "/login":
    let email = form_data.get_or_default("email", "")
    let password = form_data.get_or_default("password", "")
    
    if email == "":
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Email is required</div>"""
    elif password == "":
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Password is required</div>"""
    else:
      let user_opt = get_user_by_email(db_conn, email)
      if user_opt.is_some and verify_password(password, user_opt.get().password_hash):
        let session_id = generate_session_id()
        with_lock sessions_lock:
          sessions[session_id] = Session(user_id: user_opt.get().id, email: email)
        headers = new_http_headers([
          ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
          ("HX-Redirect", "/dashboard?success=login")
        ])
        response_body = """<div class="success" style="background-color: var(--pico-ins-background-color); color: var(--pico-ins-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Login successful! Redirecting...</div>"""
      else:
        response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Invalid email or password</div>"""

  of "/signup":
    let passkey = to_upper_ascii(form_data.get_or_default("passkey", ""))
    if passkey == "":
      echo "Passkey is required"
    let name = form_data.get_or_default("name", "")
    let email = form_data.get_or_default("email", "")
    let password = form_data.get_or_default("password", "")
    let color = form_data.get_or_default("color", "#3b82f6")
    
    if passkey == "":
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Passkey is required</div>"""
    elif name == "":
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Name is required</div>"""
    elif email == "":
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Email is required</div>"""
    elif password == "":
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Password is required</div>"""
    elif not (passkey == PASSKEY):
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Invalid passkey</div>"""
    elif get_user_by_email(db_conn, email).is_some:
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Email already registered</div>"""
    else:
      try:
        let password_hash = hash_password(password)
        let user_id = create_user(db_conn, email, password_hash, name, color)
        
        let session_id = generate_session_id()
        withLock sessions_lock:
          sessions[session_id] = Session(user_id: user_id, email: email)
        
        headers = new_http_headers([
          ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
          ("HX-Redirect", "/dashboard?success=signup")
        ])
        response_body = """<div class="success" style="background-color: var(--pico-ins-background-color); color: var(--pico-ins-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Account created successfully!</div>"""
      except:
        response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Error creating account</div>"""

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
  
  return (response_body, status, headers)
