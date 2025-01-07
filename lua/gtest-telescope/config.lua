--- @class GTest_Config
--- @field executables_folder string Path containing the test executables
--- @field executables_pattern string|string[] Pattern(s) to identify gtest executables
--- @field telescope table Custom configuration for the telescope picker
--- @field toggleterm table Custom configuration for the toggleterm terminal
--- @field dap_config table Dap config
--- @field update function

local default_config = {
    executables_folder = "build/clang/bin",
    executables_pattern = "{unit,integration}_test_*",
    telescope = {
        sorting_strategy = "ascending",
        -- layout_strategy = 'vertical',
        -- layout_config = { width = 0.5 },
        attach_mappings = function(_, map)
            map({ "i", "n" }, "<M-a>", function(_prompt_bufnr)
                require("telescope.actions").select_all(_prompt_bufnr)
            end, { noremap = true, silent = true })
            map({ "i", "n" }, "<M-x>", function(_prompt_bufnr)
                require("telescope.actions").drop_all(_prompt_bufnr)
            end, { noremap = true, silent = true })
            return true
        end,
    },
    toggleterm = {},
    dap_config = {
        type = "cppdbg",
        request = "launch",
    },
}

--- @type GTest_Config
local M = vim.deepcopy(default_config)

---@param opts table
M.update = function(opts)
    -- local newconf = vim.tbl_deep_extend("force", default_config, opts or {})
    --
    -- for k, v in pairs(newconf) do
    --     M[k] = v
    -- end
    M = vim.tbl_deep_extend("keep", opts or {}, M)

    M.executables_folder = vim.fs.normalize(M.executables_folder)
end

return M
