import db_connector/db_sqlite
import strutils, options
from times import DateTime, parse
import models

proc get_user_by_email*(db: DbConn, email: string): Option[User] =
  let row = db.get_row(sql"SELECT id, email, password_hash, name, color, avatar_filename, created_at FROM users WHERE email = ?", email)
  if row[0] == "":
    return none(User)
  
  return some(User(
    id: parse_biggest_int(row[0]),
    email: row[1],
    password_hash: row[2],
    name: row[3],
    color: row[4],
    avatar_filename: if row[5] == "": "" else: row[5],
    created_at: parse(row[6], "yyyy-MM-dd HH:mm:ss")
  ))

proc create_user*(db: DbConn, email, password_hash, name, color: string): int64 =
  db.insertID(sql"INSERT INTO users (email, password_hash, name, color) VALUES (?, ?, ?, ?)", 
              email, password_hash, name, color)

proc update_user*(db: DbConn, user_id: int64, name, color: string) =
  db.exec(sql"UPDATE users SET name = ?, color = ? WHERE id = ?", name, color, user_id)

proc update_user_password*(db: DbConn, user_id: int64, password_hash: string) =
  db.exec(sql"UPDATE users SET password_hash = ? WHERE id = ?", password_hash, user_id)

proc update_user_avatar*(db: DbConn, user_id: int64, avatar_filename: string) =
  db.exec(sql"UPDATE users SET avatar_filename = ? WHERE id = ?", avatar_filename, user_id)

proc get_user_avatar*(db: DbConn, user_id: int64): string =
  let row = db.get_row(sql"SELECT avatar_filename FROM users WHERE id = ?", user_id)
  return if row[0] == "": "" else: row[0]
