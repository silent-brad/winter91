import db_connector/db_sqlite
import strutils, options, httpclient
from times import DateTime, parse
import os
import ../upload
import models

proc get_runner_by_id*(db: DbConn, runner_id: int64): Option[Runner] =
  let row = db.get_row(sql"SELECT id, family_id, name, has_custom_avatar, created_at FROM runner WHERE id = ?", runner_id)
  if row[0] == "":
    return none(Runner)
  
  return some(Runner(
    id: parse_biggest_int(row[0]),
    family_id: parse_biggest_int(row[1]),
    name: row[2],
    has_custom_avatar: row[3] == "1",
    created_at: parse(row[4], "yyyy-MM-dd HH:mm:ss")
  ))

proc get_runners_by_family*(db: DbConn, family_id: int64): seq[Runner] =
  let rows = db.get_all_rows(sql"SELECT id, family_id, name, has_custom_avatar, created_at FROM runner WHERE family_id = ? ORDER BY created_at ASC", family_id)
  
  var runners: seq[Runner] = @[]
  for row in rows:
    runners.add(Runner(
      id: parse_biggest_int(row[0]),
      family_id: parse_biggest_int(row[1]),
      name: row[2],
      has_custom_avatar: row[3] == "1",
      created_at: parse(row[4], "yyyy-MM-dd HH:mm:ss")
    ))
  
  return runners

proc create_generic_avatar(runner_id: int64, name: string) =
  # Download and upload avatar
  let avatar_url = "https://ui-avatars.com/api/?background=random&name=" & name.replace(" ", "%20") & "&format=webp"
  let client = new_http_client()
  try:
    let avatar_data = client.get_content(avatar_url)
    let avatar_filename = avatar_data.save_uploaded_file(runner_id.int_to_str() & "-" & name & ".webp", "avatars")
  finally:
    client.close()

proc create_runner_account*(db: DbConn, family_id: int64, name: string): int64 =
  let runner_id = db.insertID(sql"INSERT INTO runner (family_id, name, has_custom_avatar) VALUES (?, ?, ?)",
                              family_id, name, false)
  create_generic_avatar(runner_id, name)
  return runner_id

proc update_runner_name*(db: DbConn, runner_id: int64, name: string) =
  let runner_opt = get_runner_by_id(db, runner_id)
  if runner_opt.is_some:
    let runner = runner_opt.get()
    
    # Update the name
    db.exec(sql"UPDATE runner SET name = ? WHERE id = ?", name, runner_id)
    
    # If the user hasn't uploaded a custom avatar, keep the existing filename for now
    create_generic_avatar(runner.id, runner.name)
    # Delete the old avatar file
    remove_file("avatars/" & runner.id.int_to_str() & "-" & runner.name & ".webp")

proc update_runner_avatar*(db: DbConn, runner_id: int64, avatar_filename: string) =
  db.exec(sql"UPDATE runner SET has_custom_avatar = true WHERE id = ?", runner_id)

proc delete_runner_account*(db: DbConn, runner_id: int64) =
  # Delete associated mile entries and posts first
  db.exec(sql"DELETE FROM mile_entry WHERE runner_id = ?", runner_id)
  db.exec(sql"DELETE FROM post WHERE runner_id = ?", runner_id)
  
  # Delete the runner account
  db.exec(sql"DELETE FROM runner WHERE id = ?", runner_id)
