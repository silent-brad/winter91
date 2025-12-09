from times import DateTime

type
  User* = object
    id*: int64
    email*: string
    password_hash*: string
    name*: string
    color*: string
    avatar_filename*: string
    created_at*: DateTime

  MileEntry* = object
    id*: int64
    user_id*: int64
    miles*: float
    logged_at*: DateTime
