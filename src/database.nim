import db_connector/db_sqlite
import strutils, options, os
from times import DateTime, parse
import types

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

proc init_database*(): DbConn =
  let db = open("winter100.db", "", "", "")
  
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      name TEXT NOT NULL,
      color TEXT NOT NULL DEFAULT '#3b82f6',
      avatar_filename TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  """)
  
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS mile_entries (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      miles REAL NOT NULL,
      logged_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users (id)
    )
  """)
  
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS posts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER NOT NULL,
      text_content TEXT NOT NULL,
      image_filename TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users (id)
    )
  """)
  
  return db

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

proc log_miles*(db: DbConn, user_id: int64, miles: float) =
  db.exec(sql"INSERT INTO mile_entries (user_id, miles) VALUES (?, ?)", user_id, miles)

proc get_user_total_miles*(db: DbConn, user_id: int64): float =
  let row = db.getRow(sql"SELECT COALESCE(SUM(miles), 0) FROM mile_entries WHERE user_id = ?", user_id)
  return parseFloat(row[0])

proc get_user_last_entry*(db: DbConn, user_id: int64): Option[MileEntry] =
  let row = db.getRow(sql"SELECT id, user_id, miles, logged_at FROM mile_entries WHERE user_id = ? ORDER BY logged_at DESC LIMIT 1", user_id)
  if row[0] == "":
    return none(MileEntry)
  
  return some(MileEntry(
    id: parseBiggestInt(row[0]),
    user_id: parseBiggestInt(row[1]),
    miles: parseFloat(row[2]),
    logged_at: parse(row[3], "yyyy-MM-dd HH:mm:ss")
  ))

proc get_leaderboard*(db: DbConn): seq[tuple[user: User, total_miles: float, last_miles: Option[float], last_logged: Option[DateTime], streak: int]] =
  let rows = db.getAllRows(sql"""
    SELECT u.id, u.email, u.password_hash, u.name, u.color, u.avatar_filename, u.created_at, COALESCE(SUM(m.miles), 0) as total_miles
    FROM users u
    LEFT JOIN mile_entries m ON u.id = m.user_id
    GROUP BY u.id
    ORDER BY total_miles DESC
  """)
  
  var leaderboard: seq[tuple[user: User, total_miles: float, last_miles: Option[float], last_logged: Option[DateTime], streak: int]] = @[]
  
  for row in rows:
    let user = User(
      id: parseBiggestInt(row[0]),
      email: row[1],
      password_hash: row[2],
      name: row[3],
      color: row[4],
      avatar_filename: if row[5] == "": "" else: row[5],
      created_at: parse(row[6], "yyyy-MM-dd HH:mm:ss")
    )
    let total_miles = parseFloat(row[7])
    let last_entry = get_user_last_entry(db, user.id)
    
    var last_miles: Option[float] = none(float)
    var last_logged: Option[DateTime] = none(DateTime)
    
    if last_entry.isSome:
      last_miles = some(last_entry.get().miles)
      last_logged = some(last_entry.get().logged_at)
    
    # Calculate streak (simplified - consecutive days)
    let streak = 1  # TODO: Implement proper streak calculation
    
    leaderboard.add((user, total_miles, last_miles, last_logged, streak))
  
  return leaderboard

proc update_user*(db: DbConn, user_id: int64, name, color: string) =
  db.exec(sql"UPDATE users SET name = ?, color = ? WHERE id = ?", name, color, user_id)

proc get_user_miles_by_date*(db: DbConn, user_id: int64): seq[tuple[date: string, miles: float]] =
  let rows = db.getAllRows(sql"""
    SELECT DATE(logged_at) as date, SUM(miles) as daily_miles
    FROM mile_entries 
    WHERE user_id = ?
    GROUP BY DATE(logged_at)
    ORDER BY date DESC
    LIMIT 30
  """, user_id)
  
  var results: seq[tuple[date: string, miles: float]] = @[]
  for row in rows:
    results.add((row[0], parseFloat(row[1])))
  
  return results

proc get_user_recent_entries*(db: DbConn, user_id: int64, limit: int = 10): seq[MileEntry] =
  let rows = db.get_all_rows(sql"""
    SELECT id, user_id, miles, logged_at
    FROM mile_entries
    WHERE user_id = ?
    ORDER BY logged_at DESC
    LIMIT ?
  """, user_id, limit)
  
  var results: seq[MileEntry] = @[]
  for row in rows:
    results.add(MileEntry(
      id: parse_biggest_int(row[0]),
      user_id: parse_biggest_int(row[1]),
      miles: parse_float(row[2]),
      logged_at: parse(row[3], "yyyy-MM-dd HH:mm:ss")
    ))
  
  return results

proc update_user_password*(db: DbConn, user_id: int64, password_hash: string) =
  db.exec(sql"UPDATE users SET password_hash = ? WHERE id = ?", password_hash, user_id)


proc create_post*(db: DbConn, user_id: int64, text_content: string, image_filename: string = ""): int64 =
  db.insertID(sql"INSERT INTO posts (user_id, text_content, image_filename) VALUES (?, ?, ?)", 
              user_id, text_content, image_filename)

proc get_all_posts*(db: DbConn): seq[Post] =
  let rows = db.get_all_rows(sql"""
    SELECT p.id, p.user_id, u.name, p.text_content, p.image_filename, p.created_at
    FROM posts p
    JOIN users u ON p.user_id = u.id
    ORDER BY p.created_at DESC
  """)
  
  var posts: seq[Post] = @[]
  for row in rows:
    posts.add(Post(
      id: parse_biggest_int(row[0]),
      user_id: parse_biggest_int(row[1]),
      user_name: row[2],
      text_content: row[3],
      image_filename: row[4],
      created_at: row[5]
    ))
  
  return posts

proc update_user_avatar*(db: DbConn, user_id: int64, avatar_filename: string) =
  db.exec(sql"UPDATE users SET avatar_filename = ? WHERE id = ?", avatar_filename, user_id)

proc get_user_avatar*(db: DbConn, user_id: int64): string =
  let row = db.get_row(sql"SELECT avatar_filename FROM users WHERE id = ?", user_id)
  return if row[0] == "": "" else: row[0]
