import db_connector/db_sqlite
import strutils
import ../types

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
