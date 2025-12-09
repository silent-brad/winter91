import tables

type
  Session* = object
    user_id*: int64
    email*: string

  User_Info* = object
    name*: string
    color*: string
    initials*: string

  User_Info_2* = object
    name*: string
    email*: string
    color*: string
    initials*: string

  Entry* = object
    user*: User_Info
    total_miles*: float
    last_miles*: float
    last_logged*: string
    current_streak*: int

  Post* = object
    id*: int64
    user_id*: int64
    user_name*: string
    text_content*: string
    image_filename*: string
    created_at*: string

const
  static_dir* = "static"
  port* = 8080

var sessions* {.global.}: Table[string, Session]
