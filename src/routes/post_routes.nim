import asynchttpserver, asyncdispatch
import strutils, uri, tables, json, options, strformat
import ../database/[models, families, walkers, miles, posts]
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
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Email is required</div>"""
    elif password == "":
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Password is required</div>"""
    elif not validate_email(email):
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Invalid email format</div>"""
    else:
      # Check family account
      let family_opt = get_family_by_email(db_conn, email)
      if family_opt.is_some and verify_password(password, family_opt.get().password_hash):
        let family = family_opt.get()
        let session_id = generate_session_id()
        {.cast(gcsafe).}:
          with_lock sessions_lock:
            sessions[session_id] = Session(
              family_id: family.id,
              email: email,
              is_family_session: true
            )
        headers = new_http_headers([
          ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
          ("HX-Redirect", "/select-walker?success=login")
        ])
        response_body = """<div class="success" style="background-color: var(--success-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Login successful! Redirecting...</div>"""
      else:
        response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Invalid email or password</div>"""

  of "/signup":
    let passkey = to_upper_ascii(form_data.get_or_default("passkey", "")).strip()
    let email = form_data.get_or_default("email", "").strip()
    let password = form_data.get_or_default("password", "").strip()
    
    if passkey == "":
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Passkey is required</div>"""
    elif email == "":
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Email is required</div>"""
    elif not validate_email(email):
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Invalid email format</div>"""
    elif password == "":
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Password is required</div>"""
    elif not (passkey == PASSKEY):
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Invalid passkey</div>"""
    elif get_family_by_email(db_conn, email).is_some:
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Email already registered</div>"""
    else:
      try:
        let password_hash = hash_password(password)
        let family_id = create_family_account(db_conn, email, password_hash)
        
        let session_id = generate_session_id()
        {.cast(gcsafe).}:
          with_lock sessions_lock:
            sessions[session_id] = Session(family_id: family_id, walker_id: 0, email: email, is_family_session: true)
        
        headers = new_http_headers([
          ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
          ("HX-Redirect", "/add-walker?success=signup")
        ])
        response_body = """<div class="success" style="background-color: var(--success-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Account created successfully!</div>"""
      except Exception as e:
        echo "Error creating account: ", e.msg
        response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Error creating account</div>"""

  of "/create-walker":
    if session.is_none:
      status = Http401
      response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">You must be logged in to create walkers</div>"""
    else:
      let name = form_data.get_or_default("name", "").strip()
      
      if name == "":
        response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Name is required</div>"""
      elif not validate_name(name):
        response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Invalid name format</div>"""
      else:
        try:
          let (walker_id, avatar_filename) = create_walker_account(db_conn, session.get().family_id, name)
          
          # Switch to the new walker
          let new_session = Session(
            family_id: session.get().family_id,
            walker_id: walker_id,
            email: session.get().email,
            name: name,
            avatar_filename: avatar_filename,
            is_family_session: false
          )
          
          # Update session
          let session_id = generate_session_id()
          {.cast(gcsafe).}:
            with_lock sessions_lock:
              sessions[session_id] = new_session
            
          headers = new_http_headers([
            ("Set-Cookie", "session_id=" & session_id & "; HttpOnly; Path=/"),
            ("HX-Redirect", "/dashboard?success=walker-created")
          ])
          response_body = """<div class="success" style="background-color: var(--success-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Walker account created successfully!</div>"""
        except Exception as e:
          echo "Error creating walker: ", e.msg
          response_body = """<div class="error" style="background-color: var(--error-oklch-500); color: var(--neutral-oklch-50); padding: 1rem; border-radius: 0.375rem; margin-bottom: 1rem;">Error creating walker account</div>"""

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
          log_miles(db_conn, session.get().walker_id, miles)
          response_body = &"""<p style="color: green;">Logged {miles:.1f} miles successfully!</p>"""
      except:
        response_body = """<p style="color: red;">Invalid miles value</p>"""

  of "/post":
    if session.is_none:
      status = Http401
      response_body = """<p style="color: red;">You must be logged in to create posts</p>"""
    else:
      # Parse multipart form data for file upload
      let multipart_data = await parse_multipart(req)
      
      if multipart_data.error != "":
        response_body = &"""<p style="color: red;">Error parsing form data: {multipart_data.error}</p>"""
      else:
        let text_content = sanitize_html(multipart_data.fields.getOrDefault("text_content", "").strip())
        var image_filename = ""
        if multipart_data.files.has_key("image"):
          let (orig_filename, content_type, file_size) = multipart_data.files["image"]
          let upload_path = "uploads" / orig_filename
          if file_exists(upload_path):
            let file_data = read_file(upload_path)
            image_filename = save_uploaded_file(file_data, orig_filename, "pictures")
            # Clean up the temporary file
            remove_file(upload_path)
        
        if text_content.strip() == "" and image_filename == "":
          response_body = """<p style="color: red;">Please provide text content or an image</p>"""
        else:
          try:
            discard create_post(db_conn, session.get().walker_id, text_content, image_filename)
            headers = new_http_headers([("HX-Redirect", "/posts")])
            response_body = """<p style="color: green;">Post created successfully!</p>"""
          except Exception as e:
            echo "Error creating post: ", e.msg
            response_body = """<p style="color: red;">Error creating post</p>"""

  of "/settings":
    if session.is_none:
      status = Http401
      response_body = """<p style="color: red;">You must be logged in to update settings</p>"""
    else:
      # Parse multipart form data for file upload
      let multipart_data = await parse_multipart(req)
      
      if multipart_data.error != "":
        response_body = &"""<p style="color: red;">Error parsing form data: {multipart_data.error}</p>"""
      else:
        # Extract form fields with validation
        let name = multipart_data.fields.get_or_default("name", "").strip()
        let current_password = multipart_data.fields.get_or_default("current_password", "").strip()
        let new_password = multipart_data.fields.get_or_default("new_password", "").strip()
        let confirm_password = multipart_data.fields.get_or_default("confirm_new_password", "").strip()
        
        if name == "":
          response_body = """<p style="color: red;">Name is required</p>"""
        elif not validate_name(name):
          response_body = """<p style="color: red;">Invalid name format</p>"""
        else:
          let walker_opt = get_walker_by_id(db_conn, session.get().walker_id)
          if walker_opt.is_none:
            response_body = """<p style="color: red;">Walker not found</p>"""
          else:
            let walker = walker_opt.get()
            var success = true
            var error_msg = ""
            
            # Update basic info
            if success:
              try:
                update_walker_name(db_conn, walker.id, name)
              except:
                success = false
                error_msg = "Error updating profile"
            
            # Handle avatar upload if provided
            if success and multipart_data.files.has_key("avatar"):
              let (orig_filename, content_type, file_size) = multipart_data.files["avatar"]
              let upload_path = "uploads" / orig_filename
              if file_exists(upload_path):
                try:
                  let file_data = read_file(upload_path)
                  # Extract extension from original filename
                  let original_ext = if orig_filename.contains("."): orig_filename.split(".")[^1].to_lower_ascii() else: "jpg"
                  # Generate walker-specific filename that can be overwritten
                  let name_with_underscore = walker.name.replace(" ", "_")
                  let walker_filename = $session.get().walker_id & "_" & name_with_underscore & "." & original_ext
                  # Save to avatars directory, allowing overwrite of existing file
                  discard save_uploaded_file(file_data, walker_filename, "avatars")
                  # Clean up the temporary file
                  remove_file(upload_path)
                  # Update walker avatar flag in database
                  update_walker_avatar(db_conn, session.get().walker_id)
                except Exception as e:
                  echo "Error updating avatar: ", e.msg
                  success = false
                  error_msg = "Error updating avatar"
            
            # Handle password change if provided
            if success and current_password != "" and new_password != "":
              if new_password != confirm_password:
                success = false
                error_msg = "New passwords do not match"
              elif new_password.len < 8:
                success = false
                error_msg = "Password must be at least 8 characters"
              else:
                # Verify current family password
                let family_opt = get_family_by_id(db_conn, session.get().family_id)
                if family_opt.is_none:
                  success = false
                  error_msg = "Family account not found"
                elif not verify_password(current_password, family_opt.get().password_hash):
                  success = false
                  error_msg = "Current password is incorrect"
                else:
                  try:
                    let new_password_hash = hash_password(new_password)
                    update_family_password(db_conn, session.get().family_id, new_password_hash)
                  except:
                    success = false
                    error_msg = "Error updating password"
            
            if success:
              headers = new_http_headers([("HX-Redirect", "/dashboard?success=settings")])
              response_body = &"<p style=\"color: green;\">Settings updated successfully!</p>"
            else:
              response_body = &"""<p style="color: red;">{error_msg}</p>"""

  else:
    status = Http404
    response_body = "Endpoint not found"
  
  return (response_body, status, headers)
