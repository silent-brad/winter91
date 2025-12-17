import db_connector/db_sqlite

proc init_database*(): DbConn =
  let db = open("winter91.db", "", "", "")
  
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS family (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    )
  """)
  
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS runner (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      family_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      has_custom_avatar BOOLEAN DEFAULT FALSE,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (family_id) REFERENCES family (id)
    )
  """)
  
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS mile_entry (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      runner_id INTEGER NOT NULL,
      miles REAL NOT NULL,
      logged_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (runner_id) REFERENCES runner (id)
    )
  """)
  
  db.exec(sql"""
    CREATE TABLE IF NOT EXISTS post (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      runner_id INTEGER,
      text_content TEXT NOT NULL,
      image_filename TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (runner_id) REFERENCES runner (id)
    )
  """)
  
  return db
