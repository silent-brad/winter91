import asynchttpserver
import strutils, uri, tables, json, options, strformat
import ../database/[models, families, runners, miles, posts]
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
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location", if session.is_none: "/login" else: "/select-runner")])
    else:
      let leaderboard = get_leaderboard(db_conn)
      var user_stats: seq[Entry] = @[]
      for db_entry in leaderboard:
        var name: string = db_entry.runner.name
        var user: Runner_Info = Runner_Info(name: name, avatar: "/pictures/" & name.replace(" ", "_") & ".webp")
        var entry: Entry = Entry(
          runner: user,
          total_miles: db_entry.total_miles,
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
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location", if session.is_none: "/login" else: "/select-runner")])
    else:
      let current_total = get_user_total_miles(db_conn, session.get().runner_id)
      # Check for success parameter
      var success_msg: Option[string] = none(string)
      if req.url.query.len > 0:
        if "success=signup" in req.url.query:
          success_msg = some("Account created successfully! Welcome to Winter 100!")
        elif "success=login" in req.url.query:
          success_msg = some("Login successful! Welcome back to Winter 100!")
      response_body = render_template("dashboard.jinja", session, success_message = success_msg, current_total = some(current_total))

  of "/log":
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location", if session.is_none: "/login" else: "/select-runner")])
    else:
      let current_total = get_user_total_miles(db_conn, session.get().runner_id)
      response_body = render_template("dashboard.jinja", session, current_total = some(current_total))

  of "/posts":
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location", if session.is_none: "/login" else: "/select-runner")])
    else:
      response_body = render_posts_page(@[], session)

  of "/logout":
    if session.is_some:
      status = Http302
      headers = new_http_headers([
        ("Set-Cookie", "session_id=; HttpOnly; Path=/; Max-Age=0"),
        ("Location", "/")
      ])
    else:
      status = Http302
      headers = new_http_headers([("Location", "/")])

  of "/about":
    let user_id_opt = if session.isSome: some(session.get().runner_id) else: none(int64)
    response_body = render_template("about.jinja", session, runner_id = user_id_opt)

  # of "/family-dashboard":
  #   if session.is_none or not session.get().is_family_account:
  #     status = Http302
  #     headers = new_http_headers([("Location", "/login")])
  #   else:
  #     let runners = get_runners_by_family(db_conn, session.get().family_id)
  #     response_body = render_family_dashboard(runners, session)

  of "/add-runner":
    if session.is_none or not session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location", "/login")])
    else:
      # Check for success parameter
      var success_msg: Option[string] = none(string)
      if req.url.query.len > 0:
        if "success=signup" in req.url.query:
          success_msg = some("Family account created successfully! Now create your first runner.")
      response_body = render_template("add-runner.jinja", session, none(string), success_msg)

  of "/select-runner":
    if session.is_none or not session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location", "/login")])
    else:
      let db_runners = get_runners_by_family(db_conn, session.get().family_id)
      var runners: seq[Runner_Info] = @[]
      for runner in db_runners:
        let runner_info = Runner_Info(
          id: runner.id,
          name: runner.name,
          family_id: runner.family_id,
          has_custom_avatar: runner.has_custom_avatar,
          created_at: $runner.created_at
        )
        runners.add(runner_info)
      # Check for success parameter
      var success_msg: Option[string] = none(string)
      if req.url.query.len > 0:
        if "success=login" in req.url.query:
          success_msg = some("Login successful! Choose a runner to continue.")
      response_body = render_runner_selection(runners, session, success_message = success_msg)

  of "/settings":
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location", if session.is_none: "/login" else: "/select-runner")])
    else:
      let user_opt = get_runner_by_id(db_conn, session.get().runner_id)
      if user_opt.is_some:
        let user = user_opt.get()
        var user_info: Runner_Info = Runner_Info(name: user.name)
        response_body = render_settings(some(user_info), session, none(string), none(string))
      else:
        status = Http302
        headers = new_http_headers([("Location", "/login")])

  of "/api/leaderboard-table":
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location", if session.is_none: "/login" else: "/select-runner")])
    else:
      let leaderboard = get_leaderboard(db_conn)
      var user_stats: seq[Entry] = @[]
      for db_entry in leaderboard:
        var name: string = db_entry.runner.name
        var user: Runner_Info = Runner_Info(name: name, avatar: "/pictures/" & name.replace(" ", "_") & ".webp")
        var entry: Entry = Entry(
          runner: user,
          total_miles: db_entry.total_miles,
        )
        user_stats.add(entry)
      
      response_body = render_leaderboard_table(user_stats)

  of "/api/user-miles-data":
    if session.is_none or session.get().is_family_session:
      status = Http401
      headers = new_http_headers([("Content-Type", "application/json")])
      response_body = "{\"error\": \"Unauthorized\"}"
    else:
      headers = new_http_headers([("Content-Type", "application/json")])
      let runner_id = session.get().runner_id
      let miles_by_date = get_user_miles_by_date(db_conn, runner_id)
      let recent_entries = get_user_recent_entries(db_conn, runner_id, 10)
      
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

  of "/api/post-feed":
    if session.is_none or session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location", if session.is_none: "/login" else: "/select-runner")])
    else:
      let posts = get_all_posts(db_conn)
      response_body = render_post_feed(posts)
  
  # Handle switch-runner/ID routes
  elif req.url.path.starts_with("/switch-runner/"):
    if session.is_none or not session.get().is_family_session:
      status = Http302
      headers = new_http_headers([("Location", "/login")])
    else:
      let runner_id_str = req.url.path[15..^1]  # Remove "/switch-runner/"
      try:
        let runner_id = parse_biggest_int(runner_id_str)
        let runner_opt = get_runner_by_id(db_conn, runner_id)
        
        if runner_opt.is_none or runner_opt.get().family_id != session.get().family_id:
          status = Http302
          headers = new_http_headers([("Location", "/select-runner?error=invalid-runner")])
        else:
          # Switch to the runner
          let new_session = Session(
            family_id: session.get().family_id,
            runner_id: runner_id,
            email: session.get().email,
            is_family_session: false
          )
          
          # Update session
          let session_id = generate_session_id()
          {.cast(gcsafe).}:
            with_lock sessions_lock:
              sessions[session_id] = new_session
            
          status = Http302
          headers = new_http_headers([
            ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
            ("Location", "/dashboard")
          ])
      except:
        status = Http302
        headers = new_http_headers([("Location", "/select-runner?error=invalid-runner")])
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
          of ".webp": "image/webp"
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

    # Check if it's a avatar file request
    elif req.url.path.starts_with("/avatars/"):
      let file_path = sanitize_path(req.url.path[10..^1])  # Remove "/avatars/" and sanitize
      let full_path = "avatars" / file_path
      
      # Ensure the file is within the pictures directory and has safe extension
      if file_path.contains("..") or not full_path.starts_with("avatars/"):
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
