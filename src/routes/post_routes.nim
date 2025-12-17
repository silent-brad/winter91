import asynchttpserver, asyncdispatch
import strutils, uri, tables, json, options, strformat
import ../database/[models, families, runners, miles, posts]
import db_connector/db_sqlite
import locks
import os
from times import DateTime, epochTime, format
import ../types, ../auth, ../templates, ../utils, ../upload
import multipart

proc handle_post_routes*(req: Request, session: Option[Session], db_conn: DbConn, PASSKEY: string): Future[(string, HttpCode, HttpHeaders)] {.async.} =
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
    let email = form_data.get_or_default("email", "").strip()
    let password = form_data.get_or_default("password", "").strip()
    
    if email == "":
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Email is required</div>"""
    elif password == "":
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Password is required</div>"""
    elif not validate_email(email):
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Invalid email format</div>"""
    else:
      # Check family account
      let family_opt = get_family_by_email(db_conn, email)
      if family_opt.is_some and verify_password(password, family_opt.get().password_hash):
        let family = family_opt.get()
        let session_id = generate_session_id()
        {.cast(gcsafe).}:
          with_lock sessions_lock:
            sessions[session_id] = Session(family_id: family.id, runner_id: 0, email: email, is_family_session: true)
        headers = new_http_headers([
          ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
          ("HX-Redirect", "/select-runner?success=login")
        ])
        response_body = """<div class="success" style="background-color: var(--pico-ins-background-color); color: var(--pico-ins-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Login successful! Redirecting...</div>"""
      else:
        response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Invalid email or password</div>"""

  of "/signup":
    let passkey = to_upper_ascii(form_data.get_or_default("passkey", "")).strip()
    let email = form_data.get_or_default("email", "").strip()
    let password = form_data.get_or_default("password", "").strip()
    
    if passkey == "":
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Passkey is required</div>"""
    elif email == "":
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Email is required</div>"""
    elif not validate_email(email):
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Invalid email format</div>"""
    elif password == "":
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Password is required</div>"""
    elif not (passkey == PASSKEY):
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Invalid passkey</div>"""
    elif get_family_by_email(db_conn, email).is_some:
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Email already registered</div>"""
    else:
      try:
        let password_hash = hash_password(password)
        let family_id = create_family_account(db_conn, email, password_hash)
        
        let session_id = generate_session_id()
        {.cast(gcsafe).}:
          with_lock sessions_lock:
            sessions[session_id] = Session(family_id: family_id, runner_id: 0, email: email, is_family_session: true)
        
        headers = new_http_headers([
          ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
          ("HX-Redirect", "/add-runner?success=signup")
        ])
        response_body = """<div class="success" style="background-color: var(--pico-ins-background-color); color: var(--pico-ins-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Account created successfully!</div>"""
      except:
        response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Error creating account</div>"""

  of "/create-runner":
    if session.is_none or not session.get().is_family_session:
      status = Http401
      response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">You must be logged into a family account to create runners</div>"""
    else:
      let name = form_data.get_or_default("name", "").strip()
      
      if name == "":
        response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Name is required</div>"""
      elif not validate_name(name):
        response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Invalid name format</div>"""
      else:
        try:
          let runner_id = create_runner_account(db_conn, session.get().family_id, name)
          
          # Switch to the new runner
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
            
          headers = new_http_headers([
            ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
            ("HX-Redirect", "/dashboard?success=runner-created")
          ])
          response_body = """<div class="success" style="background-color: var(--pico-ins-background-color); color: var(--pico-ins-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Runner account created successfully!</div>"""
        except Exception as e:
          echo "Error creating runner: ", e.msg
          response_body = """<div class="error" style="background-color: var(--pico-del-background-color); color: var(--pico-del-color); padding: 1rem; border-radius: var(--pico-border-radius); margin-bottom: 1rem;">Error creating runner account</div>"""

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
          log_miles(db_conn, session.get().runner_id, miles)
          response_body = &"""<p style="color: green;">Logged {miles:.1f} miles successfully!</p>"""
      except:
        response_body = """<p style="color: red;">Invalid miles value</p>"""

  of "/post":
    if session.is_none:
      status = Http401
      response_body = """<p style="color: red;">You must be logged in to create posts</p>"""
    else:
      # Parse multipart form data for file upload
      let multipart_data = await parseMultipart(req)
      
      if multipart_data.error != "":
        response_body = &"""<p style="color: red;">Error parsing form data: {multipart_data.error}</p>"""
      else:
        let text_content = sanitize_html(multipart_data.fields.getOrDefault("text_content", "").strip())
        var image_filenames: seq[string] = @[]
        
        # Check for multiple image files
        for key, (orig_filename, content_type, file_size) in multipart_data.files:
          if key.startsWith("image"):
            let upload_path = "uploads" / orig_filename
            if file_exists(upload_path):
              let file_data = read_file(upload_path)
              let saved_filename = save_uploaded_file(file_data, orig_filename, "pictures")
              image_filenames.add(saved_filename)
              # Clean up the temporary file
              remove_file(upload_path)
        
        # For backwards compatibility, store first image in image_filename field
        let image_filename = if image_filenames.len > 0: image_filenames[0] else: ""
        
        if text_content.strip() == "" and image_filename == "":
          response_body = """<p style="color: red;">Please provide text content or an image</p>"""
        else:
          try:
            discard create_post(db_conn, session.get().runner_id, text_content, image_filename)
            headers = new_http_headers([("HX-Redirect", "/post")])
            response_body = """<p style="color: green;">Post created successfully!</p>"""
          except Exception as e:
            echo "Error creating post: ", e.msg
            response_body = """<p style="color: red;">Error creating post</p>"""

  of "/upload-avatar":
    if session.is_none:
      status = Http401
      response_body = """<p style="color: red;">You must be logged in to upload avatar</p>"""
    else:
      # Parse multipart form data for file upload
      let multipart_data = await parseMultipart(req)
      
      if multipart_data.error != "":
        response_body = &"""<p style="color: red;">Error parsing form data: {multipart_data.error}</p>"""
      else:
        var avatar_filename = ""
        
        # Check if an avatar file was uploaded
        if multipart_data.files.hasKey("avatar"):
          let (orig_filename, content_type, file_size) = multipart_data.files["avatar"]
          # Read the uploaded file from uploads directory and save to pictures
          let upload_path = "uploads" / orig_filename
          if file_exists(upload_path):
            let file_data = read_file(upload_path)
            avatar_filename = save_uploaded_file(file_data, "avatar_" & orig_filename, "pictures")
            # Clean up the temporary file
            remove_file(upload_path)
        
        if avatar_filename == "":
          response_body = """<p style="color: red;">No avatar file uploaded</p>"""
        else:
          try:
            update_runner_avatar(db_conn, session.get().runner_id, avatar_filename)
            response_body = """<p style="color: green;">Avatar updated successfully!</p>"""
          except Exception as e:
            echo "Error updating avatar: ", e.msg
            response_body = """<p style="color: red;">Error updating avatar</p>"""

  of "/settings":
    if session.is_none:
      status = Http401
      response_body = """<p style="color: red;">You must be logged in to update settings</p>"""
    else:
      # Parse multipart form data for file upload
      let multipart_data = await parseMultipart(req)
      
      if multipart_data.error != "":
        response_body = &"""<p style="color: red;">Error parsing form data: {multipart_data.error}</p>"""
      else:
        # Extract form fields with validation
        let name = multipart_data.fields.get_or_default("name", "").strip()
        let color = multipart_data.fields.get_or_default("color", "#3b82f6").strip()
        let current_password = multipart_data.fields.get_or_default("current_password", "").strip()
        let new_password = multipart_data.fields.get_or_default("new_password", "").strip()
        let confirm_password = multipart_data.fields.get_or_default("confirm_password", "").strip()
        
        var profile_picture_filename = ""
        
        # Check if a profile picture file was uploaded
        if multipart_data.files.hasKey("profile_picture"):
          let (orig_filename, content_type, file_size) = multipart_data.files["profile_picture"]
          # Read the uploaded file from uploads directory and save to pictures
          let upload_path = "uploads" / orig_filename
          if file_exists(upload_path):
            let file_data = read_file(upload_path)
            profile_picture_filename = save_uploaded_file(file_data, "avatar_" & orig_filename, "pictures")
            # Clean up the temporary file
            remove_file(upload_path)
        
        if name == "":
          response_body = """<p style="color: red;">Name is required</p>"""
        elif not validate_name(name):
          response_body = """<p style="color: red;">Invalid name format</p>"""
        elif not validate_color(color):
          response_body = """<p style="color: red;">Invalid color format</p>"""
        else:
          let runner_opt = get_runner_by_id(db_conn, session.get().runner_id)
          if runner_opt.is_none:
            response_body = """<p style="color: red;">Runner not found</p>"""
          else:
            let runner = runner_opt.get()
            var success = true
            var error_msg = ""
            
            # Handle profile picture upload if one was provided
            if profile_picture_filename != "":
              try:
                update_runner_avatar(db_conn, session.get().runner_id, profile_picture_filename)
              except Exception as e:
                echo "Error updating profile picture: ", e.msg
                success = false
                error_msg = "Error updating profile picture"
            
            # Update basic info
            if success:
              try:
                update_runner_name(db_conn, runner.id, name)
              except:
                success = false
                error_msg = "Error updating profile"
            
            # Note: Password changes are handled at the family account level, not for individual runners
            
            if success:
              response_body = """<p style="color: green;">Settings updated successfully!</p>"""
            else:
              response_body = &"""<p style="color: red;">{error_msg}</p>"""

  else:
    status = Http404
    response_body = "Endpoint not found"
  
  return (response_body, status, headers)
