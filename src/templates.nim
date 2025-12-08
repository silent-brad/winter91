import options
import nimja/parser
import os
import types

proc render_template*(template_name: static string, session: Option[Session] = none(Session), error_message: Option[string] = none(string), success_message: Option[string] = none(string), email: Option[string] = none(string), name: Option[string] = none(string), current_color: Option[string] = none(string), passkey: Option[string] = none(string), miles: Option[string] = none(string), current_total: Option[float] = none(float), user_id: Option[int64] = none(int64)): string {.gcsafe.} =
  compileTemplateFile(template_name, baseDir = get_script_dir())

proc render_leaderboard*(user_stats: seq[Entry], session: Option[Session] = none(Session), success_message: Option[string] = none(string)): string {.gcsafe.} =
  compileTemplateFile("leaderboard.jinja", baseDir = get_script_dir())

proc render_settings*(user: Option[User_Info_2], session: Option[Session] = none(Session), error_message: Option[string] = none(string), success_message: Option[string] = none(string), current_color: Option[string] = none(string), email: Option[string] = none(string)): string {.gcsafe.} =
  compileTemplateFile("settings.jinja", baseDir = get_script_dir())
