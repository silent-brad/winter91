import std/hashes, checksums/sha1
import tables, options, locks, strutils
from times import epochTime
import types

template with_lock(lock: Lock, body: untyped): untyped =
  withLock(lock):
    body

var sessions_lock*: Lock

proc hash_password*(password: string): string =
  return $secureHash(password)

proc verify_password*(password, hash: string): bool =
  return $secureHash(password) == hash

proc generate_session_id*(): string =
  let now = $epochTime()
  return $hash(now & "salt")

proc get_user_from_session*(session_id: string): Option[Session] {.gcsafe.} =
  {.cast(gcsafe).}:
    with_lock sessions_lock:
      if session_id in sessions:
        return some(sessions[session_id])
      return none(Session)
