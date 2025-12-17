import options
import nimja/parser
import os
import types

const base_dir = get_script_dir() & "/../templates/"

proc render_template*(template_name: static string, session: Option[Session] = none(Session), error_message: Option[string] = none(string), success_message: Option[string] = none(string), name: Option[string] = none(string), miles: Option[string] = none(string), current_total: Option[float] = none(float), runner_id: Option[int64] = none(int64), email: Option[string] = none(string)): string {.gcsafe.} =
  compile_template_file(template_name, base_dir)

proc render_leaderboard*(user_stats: seq[Entry], session: Option[Session] = none(Session), success_message: Option[string] = none(string)): string {.gcsafe.} =
  compile_template_file("leaderboard.jinja", base_dir)

proc render_settings*(user: Option[Runner_Info], session: Option[Session] = none(Session), error_message: Option[string] = none(string), success_message: Option[string] = none(string)): string {.gcsafe.} =
  compile_template_file("settings.jinja", base_dir)

proc render_post_page*(posts: seq[Post], session: Option[Session] = none(Session)): string {.gcsafe.} =
  compile_template_file("post.jinja", base_dir)

proc render_runner_selection*(runners: seq[Runner_Info], session: Option[Session] = none(Session), success_message: Option[string] = none(string), error_message: Option[string] = none(string)): string {.gcsafe.} =
  compile_template_file("select-runner.jinja", base_dir)

# proc render_family_dashboard*(runners: seq[Runner_Info], session: Option[Session] = none(Session), error_message: Option[string] = none(string), success_message: Option[string] = none(string)): string {.gcsafe.} =
#   compile_template_file("family_dashboard.jinja", base_dir)
