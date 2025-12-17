import db_connector/db_sqlite
import strutils
import ../types

proc create_post*(db: DbConn, runner_id: int64, text_content: string, image_filename: string = ""): int64 =
  db.insertID(sql"INSERT INTO post (runner_id, text_content, image_filename) VALUES (?, ?, ?)",
              runner_id, text_content, image_filename)

proc get_all_posts*(db: DbConn): seq[Post] =
  let rows = db.get_all_rows(sql"""
    SELECT p.id, p.runner_id, u.name, p.text_content, p.image_filename, p.created_at
    FROM post p
    JOIN runner u ON p.runner_id = u.id
    ORDER BY p.created_at DESC
  """)
  
  var posts: seq[Post] = @[]
  for row in rows:
    posts.add(Post(
      id: parse_biggest_int(row[0]),
      runner_id: parse_biggest_int(row[1]),
      name: row[2],
      text_content: row[3],
      image_filename: row[4],
      created_at: row[5]
    ))
  
  return posts
