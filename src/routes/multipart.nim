import strutils

proc parse_multipart_binary*(body: string, boundary: string): seq[tuple[name: string, filename: string, content: string, content_type: string]] =
  var parts: seq[tuple[name: string, filename: string, content: string, content_type: string]] = @[]
  
  if body.len == 0 or boundary.len == 0:
    return parts
  
  let delimiter = "--" & boundary
  let end_delimiter = delimiter & "--"
  
  var pos = 0
  
  # Find first boundary
  let first_boundary = body.find(delimiter, pos)
  if first_boundary == -1:
    return parts
  
  pos = first_boundary + delimiter.len
  
  while pos < body.len:
    # Skip CRLF after boundary
    if pos + 1 < body.len and body[pos] == '\r' and body[pos + 1] == '\n':
      pos += 2
    
    # Find next boundary or end
    let next_boundary = body.find(delimiter, pos)
    if next_boundary == -1:
      break
    
    let section = body[pos..<next_boundary]
    
    # Parse section
    let header_end = section.find("\r\n\r\n")
    if header_end == -1:
      pos = next_boundary + delimiter.len
      continue
    
    let headers = section[0..<header_end]
    let content_start = header_end + 4
    let content = section[content_start..^1]
    
    var name = ""
    var filename = ""
    var content_type = ""
    
    # Parse headers
    for line in headers.split("\r\n"):
      if line.starts_with("Content-Disposition:"):
        # Parse Content-Disposition header
        for part in line.split(";"):
          let trimmed = part.strip()
          if trimmed.starts_with("name=\""):
            name = trimmed[6..^2]
          elif trimmed.starts_with("filename=\""):
            filename = trimmed[10..^2]
      elif line.starts_with("Content-Type:"):
        content_type = line[13..^1].strip()
    
    if name.len > 0:
      parts.add((name, filename, content, content_type))
    
    pos = next_boundary + delimiter.len
    
    # Check if this is the end delimiter
    if pos + 2 < body.len and body[pos] == '-' and body[pos + 1] == '-':
      break
  
  return parts
