import strutils, os, strformat, osproc
from times import format, now

proc save_uploaded_file*(file_data: string, filename: string, directory: string = "pictures"): string =
  # Save uploaded file data to disk and return the filename
  if file_data.len == 0:
    return ""
  
  # Extract extension from original filename
  let original_ext = if filename.contains("."): filename.split(".")[^1].toLowerAscii() else: "jpg"
  
  # Generate unique filename (remove extension from filename first)
  let name_without_ext = if filename.contains("."): filename.split(".")[0..^2].join(".") else: filename
  
  # Ensure directory exists
  if not dir_exists(directory):
    create_dir(directory)
  
  # Check if file is already webp
  if original_ext == "webp":
    let unique_filename = &"{name_without_ext}.webp"
    let filepath = directory / unique_filename
    write_file(filepath, file_data)
    return unique_filename
  else:
    # Save original file temporarily
    let temp_filename = &"{name_without_ext}.{original_ext}"
    let temp_filepath = directory / temp_filename
    write_file(temp_filepath, file_data)
    
    # Convert to webp
    let webp_filename = &"{name_without_ext}.webp"
    let webp_filepath = directory / webp_filename
    
    # Use imagemagick to convert to webp
    let cmd = &"magick \"{temp_filepath}\" \"{webp_filepath}\""
    let result = exec_cmd(cmd)
    
    # Remove temporary file
    if file_exists(temp_filepath):
      remove_file(temp_filepath)
    
    if result == 0 and file_exists(webp_filepath):
      return webp_filename
    else:
      # Fallback: save original file if conversion fails
      let fallback_filename = &"{name_without_ext}.{original_ext}"
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
