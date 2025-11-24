import db_connector/db_sqlite
import strutils, times, options, os

type
  User* = object
    id*: int64
    email*: string
    password_hash*: string
    name*: string
    color*: string
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
    CREATE TABLE IF NOT EXISTS passkeys (
      code TEXT PRIMARY KEY,
      used BOOLEAN DEFAULT FALSE,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  """)
  
  # Add some default passkeys
  db.exec(sql"INSERT OR IGNORE INTO passkeys (code) VALUES (?)", "WINTER2025")
  db.exec(sql"INSERT OR IGNORE INTO passkeys (code) VALUES (?)", "WALK100")
  db.exec(sql"INSERT OR IGNORE INTO passkeys (code) VALUES (?)", "CHALLENGE")
  
  # Add passkey from environment if provided
  let env_passkey = getEnv("PASSKEY")
  if env_passkey != "":
    db.exec(sql"INSERT OR IGNORE INTO passkeys (code) VALUES (?)", env_passkey)
  
  return db

proc get_user_by_email*(db: DbConn, email: string): Option[User] =
  let row = db.getRow(sql"SELECT id, email, password_hash, name, color, created_at FROM users WHERE email = ?", email)
  if row[0] == "":
    return none(User)
  
  return some(User(
    id: parseBiggestInt(row[0]),
    email: row[1],
    password_hash: row[2],
    name: row[3],
    color: row[4],
    created_at: parse(row[5], "yyyy-MM-dd HH:mm:ss")
  ))

proc create_user*(db: DbConn, email, password_hash, name, color: string): int64 =
  db.insertID(sql"INSERT INTO users (email, password_hash, name, color) VALUES (?, ?, ?, ?)", 
              email, password_hash, name, color)

proc validate_passkey*(db: DbConn, code: string): bool =
  let row = db.getRow(sql"SELECT used FROM passkeys WHERE code = ?", code)
  return row[0] != "" and row[0] == "0"

proc use_passkey*(db: DbConn, code: string) =
  db.exec(sql"UPDATE passkeys SET used = TRUE WHERE code = ?", code)

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
    SELECT u.id, u.email, u.password_hash, u.name, u.color, u.created_at, COALESCE(SUM(m.miles), 0) as total_miles
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
      created_at: parse(row[5], "yyyy-MM-dd HH:mm:ss")
    )
    let total_miles = parseFloat(row[6])
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

proc update_user_password*(db: DbConn, user_id: int64, password_hash: string) =
  db.exec(sql"UPDATE users SET password_hash = ? WHERE id = ?", password_hash, user_id)
