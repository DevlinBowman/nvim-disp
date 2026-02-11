# nvim-disp

A minimal floating viewport for :! command output in Neovim.
It runs an external command and renders its ANSI-colored output inside a floating window.

Developed for use with lua-structprint for printf debugging
```
https://github.com/DevlinBowman/lua-structprint
```

⸻

## Installation

This is a plain Lua module.

Place it somewhere on your runtimepath, for example:

```
~/.config/nvim/lua/disp.lua
```
or as a development module:
```
~/dev/nvim-disp/disp.lua
```
If external, prepend to runtimepath:
```
vim.opt.rtp:prepend(vim.fn.expand("~/dev/nvim-disp"))
```
Then require it:

local Disp = require("disp")


⸻

## Usage

Run using argv (recommended)

```
Disp.run({ "lua", "main.lua" })
Disp.run({ "python3", "tests.py" })
```
⸻

Run using shell string
```
Disp.run("lua main.lua")
Disp.run("pytest -q")
```
This executes through your configured Neovim shell.

⸻

Behavior
	•	Output is buffered until process exit.
	•	ANSI sequences are parsed and converted to Neovim highlights.
	•	The viewport closes with:
	•	q
	•	<Esc>
	•	<CR>
	•	Leaving the window

Running a new command replaces the previous viewport.

⸻

Non-Goals
	•	Interactive terminal
	•	Streaming pseudo-terminal
	•	Background job manager
	•	Task orchestration
	•	Full shell emulation

This is a viewport, not a terminal.
