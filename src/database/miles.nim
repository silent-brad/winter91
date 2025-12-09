import db_connector/db_sqlite
import strutils, options
from times import DateTime, parse
import models

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
