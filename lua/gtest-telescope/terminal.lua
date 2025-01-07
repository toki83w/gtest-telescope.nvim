local Terminal = require("toggleterm.terminal").Terminal

local M = {}

-- TODO: LuaDoc

M.setup = function(opts)
    M.opts = vim.tbl_extend("keep", opts or {}, {
        size = nil,
        direction = nil,
        highlights = nil,
        auto_scroll = nil,
        close_on_exit = false,
        keep_after_exit = nil,
        start_in_insert = false,
        quit_on_exit = "never",
        hidden = false,
        on_create = nil,
        on_exit = nil,
    })

    -- TODO: prevent insert mode
    -- TODO: keymap to toggle terminal
    M.term = Terminal:new({
        cmd = nil,
        highlights = M.opts.highlights,
        direction = M.opts.direction,
        auto_scroll = M.opts.auto_scroll,
        close_on_exit = M.opts.close_on_exit,
        keep_after_exit = M.opts.keep_after_exit,
        start_in_insert = M.opts.start_in_insert,
        hidden = M.opts.hidden,
        count = 40,
    })
end

M.exec = function(cmd, dir)
    M.term:open(M.opts.size, M.opts.direction)
    M.term:change_dir(dir)
    M.term:send(cmd)
end

return M
