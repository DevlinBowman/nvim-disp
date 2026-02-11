-----test_flag
----------------------------------------------------------------
-- disp.lua
--
-- Run a shell command and display its ANSI-colored output
-- in a Neovim floating window (Telescope-style).
--
-- Usage:
--   :Disp lua main.lua
--
----------------------------------------------------------------

local M = {}

local current_buf = nil
local current_win = nil

----------------------------------------------------------------
-- ANSI → highlight mapping
----------------------------------------------------------------

local ANSI_FG_TO_HL = {
    ["38;5;81"]  = "Identifier", -- keys
    ["38;5;114"] = "String",
    ["38;5;215"] = "Number",
    ["38;5;203"] = "Boolean",
    ["38;5;240"] = "Comment",
    ["38;5;45"]  = "Type",
    ["38;5;141"] = "Function",
    ["38;5;214"] = "Constant",
    ["38;5;213"] = "Special",
    ["38;5;196"] = "Error",
}

----------------------------------------------------------------
-- ANSI parser
-- Consumes escape codes and produces:
--   - clean text
--   - highlight spans
----------------------------------------------------------------

local function parse_ansi(line, row, highlights)
    local out = {}
    local col = 0
    local active_hl = nil
    local i = 1

    while i <= #line do
        local s, e, code = line:find("\27%[([%d;]+)m", i)

        if s then
            -- text before escape
            if s > i then
                local text = line:sub(i, s - 1)
                out[#out + 1] = text

                if active_hl then
                    highlights[#highlights + 1] = {
                        row,
                        col,
                        col + #text,
                        active_hl,
                    }
                end

                col = col + #text
            end

            -- update active highlight
            if code == "0" then
                active_hl = nil
            else
                active_hl = ANSI_FG_TO_HL[code]
            end

            i = e + 1
        else
            -- remainder
            local text = line:sub(i)
            out[#out + 1] = text

            if active_hl then
                highlights[#highlights + 1] = {
                    row,
                    col,
                    col + #text,
                    active_hl,
                }
            end

            break
        end
    end

    return table.concat(out)
end

----------------------------------------------------------------
-- Floating window renderer
----------------------------------------------------------------

local function destroy_current()
    if current_win and vim.api.nvim_win_is_valid(current_win) then
        vim.api.nvim_win_close(current_win, true)
    end

    if current_buf and vim.api.nvim_buf_is_valid(current_buf) then
        vim.api.nvim_buf_delete(current_buf, { force = true })
    end

    current_win = nil
    current_buf = nil
end

-- disp.lua : replace the entire open_float(lines) function with this

local function open_float(lines, run_id)
    -- Only allow the most recent run to render a window
    if run_id ~= M._active_run_id then
        return
    end

    -- Tear down any existing popup (if tracked)
    destroy_current()

    current_buf = vim.api.nvim_create_buf(false, true)
    local buf = current_buf

    local clean = {}
    local highlights = {}

    for i, line in ipairs(lines) do
        clean[i] = parse_ansi(line, i - 1, highlights)
    end

    -- Buffer options (scratch, ephemeral)
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(buf, "buflisted", false)
    vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(buf, "swapfile", false)

    -- Write content
    vim.api.nvim_buf_set_option(buf, "modifiable", true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, clean)
    vim.api.nvim_buf_set_option(buf, "modifiable", false)

    local width  = math.min(120, vim.o.columns - 4)
    local height = math.min(#clean + 2, vim.o.lines - 4)

    current_win  = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        style = "minimal",
        border = "rounded",
    })
    local win    = current_win

    -- Apply highlights
    for _, hl in ipairs(highlights) do
        vim.api.nvim_buf_add_highlight(buf, -1, hl[4], hl[1], hl[2], hl[3])
    end

    -- Single authoritative close
    local function close()
        destroy_current()
    end

    -- Close on explicit keys
    vim.keymap.set("n", "q", close, { buffer = buf, nowait = true, silent = true })
    vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true, silent = true })
    vim.keymap.set("n", "<CR>", close, { buffer = buf, nowait = true, silent = true })

    -- Close when focus leaves the popup window
    vim.api.nvim_create_autocmd("WinLeave", {
        once = true,
        callback = function()
            -- Only close if this is still the active popup window
            if current_win == win then
                close()
            end
        end,
    })

    -- Prevent buffer-switching commands in this window
    for _, key in ipairs({ "<S-Left>", "<S-Right>", "<S-Up>", "<S-Down>" }) do
        vim.keymap.set("n", key, "<Nop>", { buffer = buf, nowait = true, silent = true })
    end

    for _, cmd in ipairs({ "bnext", "bprev", "buffer", "edit", "enew" }) do
        vim.keymap.set("n", ":" .. cmd .. "<CR>", "<Nop>", { buffer = buf, nowait = true, silent = true })
    end
end

----------------------------------------------------------------
-- Public runner
----------------------------------------------------------------

-- disp.lua : replace the entire M.run(cmd) function with this

function M.run(cmd)
    local output = {}

    M._active_run_id = (M._active_run_id or 0) + 1
    local run_id = M._active_run_id

    destroy_current()

    local job_cmd

    if type(cmd) == "table" then
        job_cmd = cmd
    elseif type(cmd) == "string" then
        -- Allow string form, but explicitly through shell
        job_cmd = { vim.o.shell, vim.o.shellcmdflag, cmd }
    else
        error("disp.run: cmd must be string or table")
    end

    vim.fn.jobstart(job_cmd, {
        stdout_buffered = true,
        stderr_buffered = true,

        env = {
            EDITOR     = "",
            VISUAL     = "",
            GIT_EDITOR = "",
            PAGER      = "cat",
            GIT_PAGER  = "cat",
        },

        on_stdout = function(_, data)
            if not data then return end
            for _, line in ipairs(data) do
                output[#output + 1] = line
            end
        end,

        on_stderr = function(_, data)
            if not data then return end
            for _, line in ipairs(data) do
                output[#output + 1] = line
            end
        end,

        on_exit = function()
            if run_id ~= M._active_run_id then
                return
            end

            if #output == 0 then
                output = { "<no output>" }
            end

            vim.schedule(function()
                open_float(output, run_id)
            end)
        end,
    })
end

return M
