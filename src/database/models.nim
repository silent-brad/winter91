from times import DateTime

type
  Family* = object
    id*: int64
    email*: string
    password_hash*: string
    created_at*: DateTime

  Runner* = object
    id*: int64
    family_id*: int64
    name*: string
    has_custom_avatar*: bool
    created_at*: DateTime

  MileEntry* = object
    id*: int64
    runner_id*: int64
    miles*: float
    logged_at*: DateTime
