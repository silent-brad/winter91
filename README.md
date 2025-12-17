# <img src="./static/images/logo.svg" alt="Winter91 Logo" style="height:5rem;width:5rem;" /> Winter 91 Challenge

Made with:
<code><img width="30" height="30" src="https://api.iconify.design/devicon:nim.svg"></code>&nbsp;
<code><img width="30" height="30" src="https://api.iconify.design/devicon:htmx.svg"></code>&nbsp;
<code><img width="30" height="30" src="https://api.iconify.design/vscode-icons:file-type-nix.svg"></code>&nbsp;
<code><img width="30" height="30" src="https://api.iconify.design/vscode-icons:file-type-sqlite.svg"></code>&nbsp;
<code><img width="30" height="30" src="https://api.iconify.design/devicon:html5.svg"></code>&nbsp;
<code><img width="30" height="30" src="https://api.iconify.design/devicon:css3.svg"></code>&nbsp;

Read the [DEPS.md](DEPS.md) file for the (small) list of dependencies.

## Setup Commands
- Enable flakes in your Nix config (`/etc/nixos/configuration.nix`): `nix.settings.experimental-features = [ "nix-command" "flakes" ];`
- Run `nix develop` to enter the shell
- Create a file named `.PASSKEY.txt` which contains the passkey
- Run `nix build`
- Run `./result/bin/app`
