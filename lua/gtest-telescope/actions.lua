local transform_mod = require("telescope.actions.mt").transform_mod

local M = {}

M.go_to_test_definition = function(prompt_bufnr)
    require("telescope.actions.set").select(prompt_bufnr, "default")
end

M = transform_mod(M)

return M
