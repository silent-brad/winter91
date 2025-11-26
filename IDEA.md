# Winter 100 IDEA Phase 1

## TODO
- [x] Add dashboard/progress page
- [x] Add graph showing progress over days

- [ ] Create `DEPS.md` file to list all dependencies

## Tech stack
- Nix (<https://nixos.org/>)
- Nim
  - std/asynchttpserver
  - dbconnector (docs: <https://nim-lang.org/docs/db_sqlite.html>, repo: <https://github.com/nim-lang/db_connector>)
  - Nimja templating (<https://github.com/enthus1ast/nimja>)
- SQLite (<https://www.sqlite.org/index.html>)
- Pico.css (<https://picocss.com/>)
- HTMX (<https://htmx.org>)
  - Websockets for real time updates of other runners (on the leaderboard page)

## Pages
### Template
- Header (includes Winter 100 logo on the left and links to "About", "Leaderboard", "Log", "Log in" and "Sign up")
- Body
- Footer (Made by *Brad White* at (github icon) *Repo* (link to github repo) and date (2025-2026))

### Landing page
- Hero text `“Above all, do not lose your desire to walk. Everyday, I walk myself into a state of well-being and walk away from every illness. I have walked myself into my best thoughts, and I know of no thought so burdensome that one cannot walk away from it. But by sitting still, and the more one sits still, the closer one comes to feeling ill. Thus if one just keeps on walking, everything will be all right.” — Søren Kierkegaard`
- Hero buttons "Sign up" and "Log in"

### Leaderboard page
- Card with:
  - Table with:
    - Avatar with color and initials
    - Name
    - Miles (also include miles progress bar ending at 100 miles)
    - Last miles logged (example: "+5" for someone who last ran 5 miles)
    - Last miles logged by (example: "2 days ago", "1 day ago", "1 week ago", "2 months ago")
    - Current streak (example: "3 day streak")

### Log Miles page
- Card with:
  - Title text "Log Miles"
  - Miles input that accepts numbers and can be clicked up/down to increase/decrease
  - Submit button
  - Error message if user tries to submit a negative number
  - Success message if user submits a positive number
  - Error message if user submits a number that is not a number
  - Success message if user submits a number that is a number

### Log in page
- Card with:
  - Title text "Log in"
  - Email input
  - Password input
  - Submit button
  - Error message if user tries to submit without entering an email
  - Error message if user tries to submit without entering a password
  - Error message if user tries to submit with an invalid email
  - Error message if user tries to submit with an invalid password
  - Success message if user submits with a valid email and password

### Sign up page
- Card with:
  - Passkey code input
  - Email input
  - Password input
  - Submit button
  - Error message if user tries to submit without entering a passkey code
  - Error message if user tries to submit without entering a username
  - Error message if user tries to submit without entering a password
  - Error message if user tries to submit with an invalid passkey code
  - Error message if user tries to submit with an invalid username
  - Error message if user tries to submit with an invalid password
  - Success message if user submits with a valid passkey code, username and password

### Settings page
- Card with:
  - Title text "Settings"
  - Profile picture input
  - Email input
  - Colorpicker (if user changes color, change their profile picture to thier initials and color)
  - Password input
  - Submit button
  - Error message if user tries to submit without entering a profile picture
  - Error message if user tries to submit without entering a username
  - Error message if user tries to submit without entering a password
  - Error message if user tries to submit with an invalid profile picture
  - Error message if user tries to submit with an invalid username
  - Error message if user tries to submit with an invalid password
  - Success message if user submits with a valid profile picture, username and password

