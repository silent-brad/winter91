import strutils, os, strformat, random
from times import format, now

proc generate_random_filename*(extension: string = "webp"): string =
  # Generate random filename with letters, numbers, hyphens, and underscores
  let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
  var result = ""
  for i in 0..<16:  # Generate 16 character filename
    result.add(chars[rand(chars.len - 1)])
  return result & "." & extension

proc save_uploaded_file*(file_data: string, filename: string, directory: string = "pictures"): string =
  # Save uploaded file data to disk and return the filename
  if file_data.len == 0:
    return ""
  
  # Extract extension from original filename
  let original_ext = if filename.contains("."): filename.split(".")[^1].to_lower_ascii() else: "jpg"
  
  # Generate random filename
  let random_filename = generate_random_filename("webp")
  
  # Ensure directory exists
  if not dir_exists(directory):
    create_dir(directory)
  
  # Check if file is already webp
  if original_ext == "webp":
    let filepath = directory / random_filename
    write_file(filepath, file_data)
    return random_filename
  else:
    # Save original file temporarily with random name
    let temp_filename = generate_random_filename(original_ext)
    let temp_filepath = directory / temp_filename
    write_file(temp_filepath, file_data)
    
    # Convert to webp with random filename
    let webp_filepath = directory / random_filename
    
    # Use ImageMagick to convert to webp and resize
    try:
      var magick_cmd: string
      
      # Build ImageMagick command based on directory
      if directory == "avatars":
        # Resize to 400x400 square for avatars
        magick_cmd = &"magick \"{temp_filepath}\" -auto-orient -resize 400x400^ -gravity center -crop 400x400+0+0 +repage \"{webp_filepath}\""
      else:
        # Resize to max width 600 for other images, maintain aspect ratio
        magick_cmd = &"magick \"{temp_filepath}\" -auto-orient -resize 600 \"{webp_filepath}\""
      
      # Execute ImageMagick command
      let result = exec_shell_cmd(magick_cmd)
      
      if result == 0 and file_exists(webp_filepath):
        # Remove temporary file after successful conversion
        if file_exists(temp_filepath):
          remove_file(temp_filepath)
        return random_filename
      else:
        raise new_exception(IOError, "ImageMagick conversion failed")
        
    except Exception as e:
      # Fallback: save original file if conversion fails
      echo &"Image conversion failed: {e.msg}, saving original file"
      # Remove the temp file since we're keeping the original
      if file_exists(temp_filepath):
        remove_file(temp_filepath)
      # Save original file with original extension but random name
      let fallback_filename = generate_random_filename(original_ext)
      let fallback_filepath = directory / fallback_filename
      write_file(fallback_filepath, file_data)
      return fallback_filename

proc parse_multipart_form*(body: string, boundary: string): seq[tuple[name: string, filename: string, content: string]] =
  # Parse multipart form data and extract file uploads
  var parts: seq[tuple[name: string, filename: string, content: string]] = @[]
  
  if body.len == 0 or boundary.len == 0:
    return parts
  
  let delimiter = "--" & boundary
  let sections = body.split(delimiter)
  
  for section in sections:
    if section.strip().len == 0 or section.strip() == "--":
      continue
    
    let lines = section.split("\r\n")
    if lines.len < 3:
      continue
    
    var name = ""
    var filename = ""
    var content = ""
    var content_start = -1
    
    # Parse headers
    for i, line in lines:
      if line.starts_with("Content-Disposition:"):
        # Extract name and filename from header
        for part in line.split(";"):
          let trimmed = part.strip()
          if trimmed.starts_with("name=\""):
            name = trimmed[6..^2]  # Remove name=" and "
          elif trimmed.starts_with("filename=\""):
            filename = trimmed[10..^2]  # Remove filename=" and "
      elif line.strip().len == 0 and content_start == -1:
        content_start = i + 1
        break
    
    # Extract content
    if content_start > 0 and content_start < lines.len:
      var content_lines: seq[string] = @[]
      for i in content_start..<lines.len:
        if lines[i].strip() == "--":
          break
        content_lines.add(lines[i])
      content = content_lines.join("\r\n").strip()
    
    if name.len > 0:
      parts.add((name, filename, content))
  
  return parts
