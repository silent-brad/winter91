import asynchttpserver
import strutils, uri, tables, json, options, strformat
import ../database/[models, users, miles, posts]
import db_connector/db_sqlite
import locks
import os
from times import DateTime, epochTime, format
import ../types, ../auth, ../templates, ../utils

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

  of "/post":
    if session.is_none:
      status = Http302
      headers = new_http_headers([("Location", "/login")])
    else:
      let posts = get_all_posts(db_conn)
      response_body = render_post_page(posts, session)

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
      let file_path = sanitize_path(req.url.path[8..^1])  # Remove "/static/" and sanitize
      let full_path = "static" / file_path
      
      # Ensure the file is within the static directory
      if file_path.contains("..") or not full_path.starts_with("static/"):
        status = Http403
        response_body = "Access denied"
      elif file_exists(full_path):
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
    # Check if it's a picture file request
    elif req.url.path.starts_with("/pictures/"):
      let file_path = sanitize_path(req.url.path[10..^1])  # Remove "/pictures/" and sanitize
      let full_path = "pictures" / file_path
      
      # Ensure the file is within the pictures directory and has safe extension
      if file_path.contains("..") or not full_path.starts_with("pictures/"):
        status = Http403
        response_body = "Access denied"
      elif not is_safe_file_extension(file_path):
        status = Http403
        response_body = "File type not allowed"
      elif file_exists(full_path):
        let ext = split_file(full_path).ext.to_lower_ascii()
        let content_type = case ext:
          of ".png": "image/png"
          of ".jpg", ".jpeg": "image/jpeg"
          of ".gif": "image/gif"
          of ".webp": "image/webp"
          else: "application/octet-stream"
        
        headers = new_http_headers([("Content-Type", content_type)])
        response_body = read_file(full_path)
      else:
        status = Http404
        response_body = "File not found"
    else:
      status = Http404
      response_body = render_template("404.jinja", session)
  
  return (response_body, status, headers)
