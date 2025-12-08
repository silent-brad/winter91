import strutils, uri, tables

proc parse_form_data*(body: string): Table[string, string] =
  result = init_table[string, string]()
  if body.len == 0:
    return
  
  for pair in body.split("&"):
    let parts = pair.split("=", 1)
    if parts.len == 2:
      let key = parts[0].decode_url()
      let value = parts[1].decode_url()
      result[key] = value
