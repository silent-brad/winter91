# Winter 100 IDEA Phase 1

## TODO
- [x] Add dashboard/progress page
- [x] Add graph showing progress over days
- [x] Make graph forward instead of backwards

- [x] Create `DEPS.md` file to list all dependencies
- [x] Add HTMX/Chart.js files to the static folder

## Tech stack
- Nix (<https://nixos.org/>)
- Nim
  - std/asynchttpserver
  - dbconnector (docs: <https://nim-lang.org/docs/db_sqlite.html>, repo: <https://github.com/nim-lang/db_connector>)
  - Nimja templating (<https://github.com/enthus1ast/nimja>)
- SQLite (<https://www.sqlite.org/index.html>)
- Pico.css (<https://picocss.com/>)
- HTMX (<https://htmx.org>)
  - Websockets for real time updates of other runners (on the leaderboard page) <- ?
