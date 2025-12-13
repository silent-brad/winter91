import db_connector/db_sqlite

proc init_database*(): DbConn =
  let db = open("winter91.db", "", "", "")
  
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
