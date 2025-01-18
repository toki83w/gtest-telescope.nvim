--- @class gtest-telescope.config.Icon
--- @field icon string
--- @field hl_group string

--- @class gtest-telescope.config.Icons
--- @field success gtest-telescope.config.Icon
--- @field failure gtest-telescope.config.Icon

--- @class gtest-telescope.Config
--- @field executables_folder string Path containing the test executables
--- @field executables_pattern string|string[] Pattern(s) to identify gtest executables
--- @field mappings table Mappings for the telescope picker
--- @field telescope table Custom configuration for the telescope picker
--- @field toggleterm gtest-telescope.config.Terminal Custom configuration for the toggleterm terminal
--- @field dap_config table Dap config
--- @field icons gtest-telescope.config.Icons
--- @field update function
--- @field _suites_only boolean private

local default_config = {
    executables_folder = "build/clang/bin",
    executables_pattern = "{unit,integration}_test_*",
    mappings = {
        ["<M-a>"] = "select_all",
        ["<M-x>"] = "drop_all",
        ["<M-CR>"] = require("gtest-telescope.actions").go_to_test_definition,
        ["<M-Tab>"] = require("gtest-telescope.actions").toggle_show_test_suites_only,
    },
    telescope = {
        sorting_strategy = "ascending",
        -- layout_strategy = 'vertical',
        -- layout_config = { width = 0.5 },
    },
    toggleterm = {},
    dap_config = {
        type = "cppdbg",
        request = "launch",
    },
    icons = {
        failure = {
            icon = "",
            hl_group = "DiagnosticError",
        },
        success = {
            icon = "",
            hl_group = "DiagnosticOk",
        },
    },

    _suites_only = false,
}

--- @type gtest-telescope.Config
local M = vim.deepcopy(default_config)

---@param opts table
M.update = function(opts)
    for k, v in pairs(opts or {}) do
        M[k] = v
    end

    if M.executables_folder:sub(1, 1) ~= "/" then
        M.executables_folder = vim.fs.joinpath(vim.fn.getcwd(), M.executables_folder)
    end
    M.executables_folder = vim.fs.normalize(M.executables_folder)
end

return M
