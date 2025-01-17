local Terminal = require("toggleterm.terminal").Terminal

--- @class gtest-telescope.TerminalConfig
--- @field size number?
--- @field direction 'float'|'vertical'|'horizontal'|'tab'?
--- @field highlights ToggleTermHighlights?
--- @field auto_scroll boolean?
--- @field close_on_exit boolean?
--- @field keep_after_exit boolean?
--- @field start_in_insert boolean?
--- @field hidden boolean?
--- @field toggle_mapping string|string[]?
--- @field display_name string

--- @class gtest-telescope.Terminal
--- @field setup function(opts: gtest-telescope.TerminalConfig)
--- @field exec function(cmd: string, dir: string)
--- @field toggle_term function()

--- @type Terminal
local term

--- @type gtest-telescope.TerminalConfig
local config

local M = {}

--- @param opts gtest-telescope.TerminalConfig
--- @param on_output_line function(string)
M.setup = function(opts, on_output_line)
    config = vim.tbl_extend("keep", opts or {}, {
        display_name = "gtest-telescope",
        size = nil,
        direction = nil,
        highlights = nil,
        auto_scroll = nil,
        close_on_exit = true,
        keep_after_exit = nil,
        start_in_insert = false,
        hidden = false,
    })

    term = Terminal:new({
        cmd = nil,
        display_name = config.display_name,
        highlights = config.highlights,
        direction = config.direction,
        auto_scroll = config.auto_scroll,
        close_on_exit = config.close_on_exit,
        keep_after_exit = config.keep_after_exit,
        start_in_insert = config.start_in_insert,
        insert_mappings = false,
        hidden = config.hidden,
        count = 40,
        on_create = function(t)
            -- prevent from entering insert mode
            vim.keymap.set("n", "i", "<Nop>", { buffer = t.bufnr })
            vim.keymap.set("n", "I", "<Nop>", { buffer = t.bufnr })
            vim.keymap.set("n", "a", "<Nop>", { buffer = t.bufnr })
            vim.keymap.set("n", "A", "<Nop>", { buffer = t.bufnr })

            -- send Ctrl-C to the terminal (ascii code for Ctrl-C is 3)
            vim.keymap.set("n", "<C-c>", function()
                t:send("\x03", false)
            end, { buffer = t.bufnr })
        end,
        on_stdout = function(_, _, data, _)
            for _, line in ipairs(data) do
                -- remove color codes
                on_output_line(string.gsub(line, "%b\27m", ""))
            end
        end,
    })
end

--- @param cmd string
--- @param dir string
M.exec = function(cmd, dir)
    term:open(config.size, config.direction)
    term:change_dir(dir)
    term:send(cmd)
end

M.toggle_term = function()
    term:toggle()
end

M.kill_term = function()
    term:shutdown()
end

--- @type gtest-telescope.Terminal
return M
