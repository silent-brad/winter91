# TODO

## Big ones
- [ ] Fix graph in dashboard to work correctly

- [x] Resize pictures

- [ ] Fix WYSIWYG editor to only include B,I,U,Quote,Link

- [ ] Add avatar change

- [ ] Add styling (Basecoat)
- [ ] Add custom color scheme/css

- [ ] Make PWA
- [ ] Redo logo
- [ ] Deploy

## Full list
- [x] Add dashboard/progress page
- [x] Add graph showing progress over days
- [x] Make graph forward instead of backwards
- [x] Create `DEPS.md` file to list all dependencies
- [x] Add HTMX/Chart.js files to the static folder
- [ ] Fix graph in dashboard to work correctly

- [x] Add 404 page
- [x] Prevent server-side injection

## Fix accounts
- [x] Add avatar component (avatar icon on left, Name on right)
- [x] Make email username for family account
  - [x] Make family account create walker (user) accounts (Name, avatar)
  - [x] Generate default avatar with initials of name (just make `Name-avatar.webp`) (use this link: `https://ui-avatars.com/api/?background=random&name=Elijah%20White&format=png`)
- [x] Add text in login page: "If you need to change your password, email brad@knightoffaith.systems."
- [ ] Add avatar change
- [ ] Add remove family member?
- [ ] Add account deletion?

## Fix editor/sharing
- [ ] Fix WYSIWYG editor to only include B,I,U,Quote,Link
- [x] In leaderboard, remove fields past progress bar and fix he htmx:swaperror that causes refetch to fetch header/footer
- [x] On landing page, don't show buttons when logged in
- Make chart in dashboard show miles ran per day and make it not filled

- [x] Convert images to WebP?

- [x] Add pictures/text sharing
  - [ ] Add ability to post multiple pictures??
  - [ ] Add notifications?
  - [x] Add minimal WYSIWYG editor formatting to text in "post" route

## Fix UI/UX
- [ ] Create brand identity
  - [ ] Color scheme (winter pastel dreamlandesque)
  - [x] Create logo
- [ ] Add custom CSS (winter theme with light/dark mode)
  - [ ] Add neumorphism

- [x] Remove `nimdotenv` lib and simply create a text file (`.PASSKEY.txt`) that stores passkey and create a simple function which gets this

- [ ] Make PWA

## Deploy
- [ ] Install Nix on Laptop (currently running Mint) (run: `sh <(curl https://nixos.org/nix/install) --daemon`) and also (IMPORTANT!) enable flakes
<!-- - [ ] Clone repo, create `.env` file with `PASSKEY` and build project (`nix build`)-->
- [ ] Clone repo, create `.PASSKEY.txt` file and build project (`nix build`)
- [ ] Run `./result/bin/app` and deploy to NGrok
- [ ] In Namecheap/Cloudflare map subdomain (winter91) to NGrok URL


- [ ] Add Rive animations?

