import asynchttpserver
import strutils, uri, tables, json, options, strformat
import ../database/[models, users, miles, posts]
import db_connector/db_sqlite
import locks
import os
from times import DateTime, epochTime, format
import ../types, ../auth, ../templates, ../utils, ../upload
import multipart

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

  of "/post":
    if session.is_none:
      status = Http401
      response_body = """<p style="color: red;">You must be logged in to create posts</p>"""
    else:
      # Handle multipart form data
      var boundary = ""

      if req.headers.has_key("content-type"):
        let content_type = req.headers["content-type"]
        if content_type.contains("multipart/form-data"):
          for part in content_type.split(";"):
            let trimmed = part.strip()
            if trimmed.starts_with("boundary="):
              boundary = trimmed[9..^1]
              # Remove quotes if present
              if boundary.starts_with("\"") and boundary.ends_with("\""):
                boundary = boundary[1..^2]
      
      var text_content = ""
      var image_filename = ""
      
      # Parse multipart form if boundary exists
      if boundary.len > 0:
        let form_parts = parse_multipart_binary(body, boundary)
        for part in form_parts:
          if part.name == "text_content":
            text_content = part.content
          elif part.name == "image":
            if part.filename.len > 0 and part.content.len > 0:
              image_filename = save_uploaded_file(part.content, part.filename, "pictures")
      else:
        # For non-multipart forms (text-only posts without files)
        text_content = form_data.get_or_default("text_content", "")
      
      if text_content.strip() == "" and image_filename == "":
        response_body = &"""<p style="color: red;">DATA: {boundary}</p>"""
      else:
        try:
          discard create_post(db_conn, session.get().user_id, text_content, image_filename)
          headers = new_http_headers([("HX-Redirect", "/post")])
          response_body = """<p style="color: green;">Post created successfully!</p>"""
        except:
          response_body = """<p style="color: red;">Error creating post</p>"""

  of "/upload-avatar":
    if session.is_none:
      status = Http401
      response_body = """<p style="color: red;">You must be logged in to upload avatar</p>"""
    else:
      # Handle multipart form data for avatar upload
      var boundary = ""
      if req.headers.has_key("content-type"):
        let content_type = req.headers["content-type"]
        if content_type.contains("multipart/form-data"):
          for part in content_type.split(";"):
            let trimmed = part.strip()
            if trimmed.starts_with("boundary="):
              boundary = trimmed[9..^1]
              # Remove quotes if present
              if boundary.starts_with("\"") and boundary.ends_with("\""):
                boundary = boundary[1..^2]
      
      if boundary.len > 0:
        let form_parts = parse_multipart_binary(body, boundary)
        for part in form_parts:
          if part.name == "avatar" and part.filename.len > 0 and part.content.len > 0:
            let avatar_filename = save_uploaded_file(part.content, "avatar_" & part.filename, "pictures")
            try:
              update_user_avatar(db_conn, session.get().user_id, avatar_filename)
              response_body = """<p style="color: green;">Avatar updated successfully!</p>"""
            except:
              response_body = """<p style="color: red;">Error updating avatar</p>"""
            break
        if response_body == "":
          response_body = """<p style="color: red;">No avatar file uploaded</p>"""
      else:
        response_body = """<p style="color: red;">Invalid file upload format</p>"""

  of "/settings":
    if session.is_none:
      status = Http401
      response_body = """<p style="color: red;">You must be logged in to update settings</p>"""
    else:
      # Handle multipart form data
      var boundary = ""
      if req.headers.has_key("content-type"):
        let content_type = req.headers["content-type"]
        if content_type.contains("multipart/form-data"):
          for part in content_type.split(";"):
            let trimmed = part.strip()
            if trimmed.starts_with("boundary="):
              boundary = trimmed[9..^1]
              # Remove quotes if present
              if boundary.starts_with("\"") and boundary.ends_with("\""):
                boundary = boundary[1..^2]

      # Extract form fields from multipart data if present
      var name = ""
      var color = "#3b82f6"
      var current_password = ""
      var new_password = ""
      var confirm_password = ""
      
      if boundary.len > 0:
        let form_parts = parse_multipart_binary(body, boundary)
        for part in form_parts:
          case part.name:
            of "name":
              name = part.content
            of "color":
              color = part.content
            of "current_password":
              current_password = part.content
            of "new_password":
              new_password = part.content
            of "confirm_password":
              confirm_password = part.content
      else:
        # Fallback to regular form data parsing
        name = form_data.get_or_default("name", "")
        color = form_data.get_or_default("color", "#3b82f6")
        current_password = form_data.get_or_default("current_password", "")
        new_password = form_data.get_or_default("new_password", "")
        confirm_password = form_data.get_or_default("confirm_password", "")
      
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
          
          # Handle profile picture upload (already parsed above)
          if boundary.len > 0:
            let form_parts = parse_multipart_binary(body, boundary)
            for part in form_parts:
              if part.name == "profile_picture" and part.filename.len > 0 and part.content.len > 0:
                let avatar_filename = save_uploaded_file(part.content, "avatar_" & part.filename, "pictures")
                try:
                  update_user_avatar(db_conn, session.get().user_id, avatar_filename)
                except:
                  success = false
                  error_msg = "Error updating profile picture"
                break
          
          # Update basic info
          if success:
            try:
              update_user(db_conn, user.id, name, color)
            except:
              success = false
              error_msg = "Error updating profile"
          
          # Handle password change if provided
          if success and (current_password != "" or new_password != "" or confirm_password != ""):
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
