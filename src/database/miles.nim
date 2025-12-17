import db_connector/db_sqlite
import strutils
from times import DateTime, parse
import models

proc log_miles*(db: DbConn, runner_id: int64, miles: float) =
  db.exec(sql"INSERT INTO mile_entry (runner_id, miles) VALUES (?, ?)", runner_id, miles)

proc get_user_total_miles*(db: DbConn, runner_id: int64): float =
  let row = db.getRow(sql"SELECT COALESCE(SUM(miles), 0) FROM mile_entry WHERE runner_id = ?", runner_id)
  return parseFloat(row[0])

proc get_user_miles_by_date*(db: DbConn, runner_id: int64): seq[tuple[date: string, miles: float]] =
  let rows = db.getAllRows(sql"""
    SELECT DATE(logged_at) as date, SUM(miles) as daily_miles
    FROM mile_entry
    WHERE runner_id = ?
    GROUP BY DATE(logged_at)
    ORDER BY date DESC
    LIMIT 30
  """, runner_id)
  
  var results: seq[tuple[date: string, miles: float]] = @[]
  for row in rows:
    results.add((row[0], parse_float(row[1])))
  
  return results

proc get_user_recent_entries*(db: DbConn, runner_id: int64, limit: int = 10): seq[MileEntry] =
  let rows = db.get_all_rows(sql"""
    SELECT id, runner_id, miles, logged_at
    FROM mile_entry
    WHERE runner_id = ?
    ORDER BY logged_at DESC
    LIMIT ?
  """, runner_id, limit)
  
  var results: seq[MileEntry] = @[]
  for row in rows:
    results.add(MileEntry(
      id: parse_biggest_int(row[0]),
      runner_id: parse_biggest_int(row[1]),
      miles: parse_float(row[2]),
      logged_at: parse(row[3], "yyyy-MM-dd HH:mm:ss")
    ))
  
  return results

proc get_leaderboard*(db: DbConn): seq[tuple[runner: Runner, total_miles: float]] =
  let rows = db.getAllRows(sql"""
    SELECT r.id, r.name, r.created_at, r.family_id, r.has_custom_avatar, COALESCE(SUM(m.miles), 0) as total_miles
    FROM runner r
    LEFT JOIN mile_entry m ON r.id = m.runner_id
    GROUP BY r.id
    ORDER BY total_miles DESC
  """)
  
  var leaderboard: seq[tuple[runner: Runner, total_miles: float]] = @[]
  
  for row in rows:
    let runner = Runner(
      id: parse_biggest_int(row[0]),
      name: row[1],
      created_at: row[2].parse("yyyy-MM-dd HH:mm:ss"),
      family_id: parse_biggest_int(row[3]),
      has_custom_avatar: row[4] == "1"
    )
    let total_miles = parse_float(row[5])
    
    leaderboard.add((runner, total_miles))
  
  return leaderboard
