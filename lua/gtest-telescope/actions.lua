local transform_mod = require("telescope.actions.mt").transform_mod

local M = {}

M.go_to_test_definition = function(prompt_bufnr)
    require("telescope.actions.set").select(prompt_bufnr, "default")
end

M.toggle_show_test_suites_only = function(prompt_bufnr)
    local config = require("gtest-telescope.config")
    config._suites_only = not config._suites_only
    require("telescope.actions.state").get_current_picker(prompt_bufnr):refresh()
end

M = transform_mod(M)

return M
