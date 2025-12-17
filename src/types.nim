import tables

type
  Session* = object
    family_id*: int64
    runner_id*: int64
    email*: string
    is_family_session*: bool  # true if logged into family account, false if in runner
  
  Runner_Info* = object
    id*: int64
    name*: string
    family_id*: int64
    avatar*: string
    has_custom_avatar*: bool
    created_at*: string

  Entry* = object
    runner*: Runner_Info
    total_miles*: float

  Post* = object
    id*: int64
    runner_id*: int64
    name*: string
    text_content*: string
    image_filename*: string
    created_at*: string

const
  static_dir* = "static"
  port* = 8080

var sessions* {.global.}: Table[string, Session]
