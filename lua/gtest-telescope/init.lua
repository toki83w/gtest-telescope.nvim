-- GTest json report
--
-- "Normal" test suite
-- {
--   "name": "AxisContextTest",
--   "tests": 2,
--   "testsuite": [
--     {
--       "name": "Configuration",
--       "file": "\/mnt\/DEV\/git\/gtest_repo\/tests\/components\/AxisTest.cpp",
--       "line": 130
--     },
--     ...
--   ]
-- }
--
-- Type-parametrized test suite
-- {
--   "name": "PortLoggerTest\/0",
--   "tests": 5,
--   "testsuite": [
--     {
--       "name": "create_noThrow_ok",
--       "type_param": "unsigned char",
--       "file": "\/mnt\/DEV\/git\/gtest_repo\/tests\/components\/PortLoggerTest.cpp",
--       "line": 58
--     },
--     ...
--   ]
-- }
--
-- Value-parametrized test suite
-- {
--   "name": "ExcitationSignalEmergencyTestSuite\/ExcitationSignalEmergencyTest",
--   "tests": 14,
--   "testsuite": [
--     {
--       "name": "ExternalPowerOffEmergency\/0",
--       "value_param": "16-byte object <90-43 A9-00 EF-62 00-00 00-00 00-00 00-00 00-00>",
--       "file": "\/mnt\/DEV\/git\/gtest_repo\/tests\/components\/ExcitationSignalTest.cpp",
--       "line": 5238
--     },
--     ...
--   ]
-- }

--- @class gtest-telescope.JsonTestItem
--- @field name string
--- @field file string
--- @field line number
--- @field type_param string?
--- @field value_param string?

--- @class gtest-telescope.JsonTestSuite
--- @field name string
--- @field testsuite gtest-telescope.JsonTestItem[]

--- @class gtest-telescope.Json
--- @field testsuites gtest-telescope.JsonTestSuite[]

--- @class gtest-telescope.JsonReport
--- @field exe string
--- @field json gtest-telescope.Json

-- FIXME: when resuming a picker, the cache needs to be validated (if exe changed, try to keep the selection)

---@enum TestState
local TestState = { NONE = 0, SUCCESS = 1, FAILURE = 2, OLD_SUCCESS = 3, OLD_FAILURE = 4 }

--- @class gtest-telescope.TestEntry
--- @field display_func function(item:table) -> string,table
--- @field test_filter string
--- @field exe string
--- @field path string?
--- @field line number?
--- @field test_suite string?
--- @field type_param string?
--- @field state TestState

--- @class gtest-telescope.MapItem
--- @field suite gtest-telescope.TestEntry
--- @field tests table<string, gtest-telescope.TestEntry>

--- @alias gtest-telescope.TestMap table<string, gtest-telescope.MapItem>

--- @class gtest-telescope.CachedTestList
--- @field tests gtest-telescope.TestEntry[] flat list of tests
--- @field map gtest-telescope.TestMap tests grouped by suite
--- @field mtime table

--- @class gtest-telescope.LastRun
--- @field on_choice function(selection:gtest-telescope.TestEntry[])
--- @field tests gtest-telescope.TestEntry[]

local config = require("gtest-telescope.config")
local terminal = require("gtest-telescope.terminal")

local __log = function(...)
    print(...)
end

local cache = {
    --- @type table<string, gtest-telescope.CachedTestList>
    test_lists = {},
    picker = nil,
    --- @type gtest-telescope.LastRun?
    last_run = nil,
}

local state_to_hl_group_map = {
    [TestState.NONE] = nil,
    [TestState.SUCCESS] = "GTestTelescopeSuccess",
    [TestState.FAILURE] = "GTestTelescopeFailure",
    [TestState.OLD_SUCCESS] = "GTestTelescopeOldSuccess",
    [TestState.OLD_FAILURE] = "GTestTelescopeOldFailure",
}

--- @param line string
local parse_output_line = function(line)
    -- [  FAILED  ] CanOpenDs402EncoderTest.Creation (20 ms)
    -- [       OK ] CanOpenDs402EncoderTest.CreationWithMissingOptions (36 ms)

    local successPattern = "%[       OK %]%s*(%w+%.%w+)"
    local failurePattern = "%[  FAILED  %]%s*(%w+%.%w+)"

    if not cache.last_run or not cache.last_run.tests or not cache.test_lists then
        return
    end

    local exe = cache.last_run.tests[1].exe

    local tests = cache.test_lists[exe]
    if not tests or not tests.tests then
        return
    end
    tests = tests.tests

    local parse = function(pattern)
        local _, _, test = string.find(line, pattern)
        return test
    end

    local set_state = function(test_name, state)
        for _, test in ipairs(tests) do
            if test.test_filter == test_name then
                test.state = state
                return
            end
        end
    end

    local test_name = parse(successPattern)
    if test_name then
        set_state(test_name, TestState.SUCCESS)
        return
    end

    test_name = parse(failurePattern)
    if test_name then
        set_state(test_name, TestState.FAILURE)
        return
    end
end

--- @return string[]
local find_executables = function()
    local search_path = config.executables_folder
    local patterns = config.executables_pattern
    local lpeg_patterns = {}

    if type(patterns) == "string" then
        lpeg_patterns = { vim.glob.to_lpeg(patterns) }
    else
        for _, pattern in ipairs(patterns) do
            table.insert(lpeg_patterns, vim.glob.to_lpeg(pattern))
        end
    end

    local exes_full = vim.fs.find(function(name, _)
        for _, pattern in ipairs(lpeg_patterns) do
            if vim.re.match(name, pattern) then
                return true
            end
        end

        return false
    end, { limit = math.huge, type = "file", path = search_path })

    local exes = {}

    for _, exe in ipairs(exes_full) do
        assert(exe:sub(1, #search_path) == search_path)
        table.insert(exes, exe:sub(#search_path + 2))
    end

    return exes
end

--- @param executable string
--- @return gtest-telescope.JsonReport?
local generate_gtest_report = function(executable)
    -- FIX: Run this command asynchronously in case the gtest command is slow
    -- Hint: see plenary.async

    local tmp_path = vim.fn.tempname()
    local gtest_args = { executable, "--gtest_list_tests", "--gtest_output=json:" .. tmp_path }
    local obj = vim.system(gtest_args, { text = true }):wait()

    if obj.code ~= 0 or obj.stdout == "" then
        error("Couldn't fetch tests from executable " .. executable .. ":\n" .. obj.stdout .. "\n" .. obj.stderr)
        return
    end

    local f = io.open(tmp_path)
    if not f then
        error("Could not read json file with list of tests for executable " .. executable)
        return
    end
    local json_str = f:read("*a")
    f:close()

    local json_obj = vim.json.decode(json_str)
    if not json_obj then
        error("Couldn't decode json for executable " .. executable)
        return
    end

    return { exe = executable, json = json_obj }
end

--- @param path string
--- @return table<string, number>
local get_mtime = function(path)
    local st = vim.uv.fs_stat(path)

    if not st then
        return { sec = 0, nsec = 0 }
    end

    return st.mtime
end

--- @param suite_name string
--- @param type_param string?
--- @param exe string
--- @return gtest-telescope.TestEntry
local make_entry_for_test_suite = function(suite_name, type_param, exe)
    local text = suite_name

    if type_param then
        text = text .. "  [" .. type_param .. "]"
    end

    local f = function(item)
        local style = { { { #suite_name, #text }, "TelescopeResultsComment" } }

        if item.value.state ~= TestState.NONE then
            table.insert(style, 1, { { 0, #suite_name }, state_to_hl_group_map[item.value.state] })
        end

        return text, style
    end

    return {
        display_func = f,
        test_filter = suite_name .. ".*",
        exe = exe,
        path = nil,
        line = nil,
        test_suite = nil,
        type_param = nil,
        state = TestState.NONE,
    }
end

--- @param test gtest-telescope.JsonTestItem
--- @param suite_name string
--- @param exe string
--- @return gtest-telescope.TestEntry
local make_entry_for_single_test = function(test, suite_name, exe)
    local text = "  " .. test.name .. "  " .. suite_name

    local f = function(item)
        local style = { { { 2 + #test.name + 2, #text }, "TelescopeResultsComment" } }

        if item.value.state ~= TestState.NONE then
            table.insert(style, 1, { { 0, 2 + #test.name }, state_to_hl_group_map[item.value.state] })
        end

        return text, style
    end

    return {
        display_func = f,
        test_filter = suite_name .. "." .. test.name,
        exe = exe,
        path = test.file,
        line = test.line,
        test_suite = suite_name,
        type_param = test.type_param,
        state = TestState.NONE,
    }
end

--- @param report gtest-telescope.JsonReport
--- @return gtest-telescope.TestEntry[], gtest-telescope.TestMap
local generate_test_list_from_report = function(report)
    local list = {}
    local map = {}

    for _, testsuite in ipairs(report.json.testsuites) do
        local type_param
        local map_item = { tests = {}, suite = nil }

        for _, test in ipairs(testsuite.testsuite) do
            local test_entry = make_entry_for_single_test(test, testsuite.name, report.exe)
            table.insert(list, test_entry)
            map_item.tests[test.name] = test_entry

            if test.type_param then
                type_param = test.type_param
            end
        end

        local suite_entry = make_entry_for_test_suite(testsuite.name, type_param, report.exe)
        table.insert(list, suite_entry)
        map_item.suite = suite_entry
        map[testsuite.name] = map_item
    end

    return list, map
end

--- @param map gtest-telescope.TestMap
local set_suites_state = function(map)
    -- at least one failure -> failure
    -- at least one old failure -> old failure
    -- all success -> success
    -- all old success -> old success
    for _, item in pairs(map) do
        local all_old_success = true
        local all_success = true
        local state = TestState.NONE

        for _, test in pairs(item.tests) do
            all_success = all_success and test.state == TestState.SUCCESS
            all_old_success = all_old_success and test.state == TestState.OLD_SUCCESS

            if test.state == TestState.FAILURE then
                state = TestState.FAILURE
                break
            end

            if test.state == TestState.OLD_FAILURE then
                state = TestState.OLD_FAILURE
            end
        end

        if all_success then
            item.suite.state = TestState.SUCCESS
        elseif all_old_success then
            item.suite.state = TestState.OLD_SUCCESS
        else
            item.suite.state = state
        end
    end
end

--- @param tests gtest-telescope.TestEntry[]
local set_suites_state_from_list = function(tests)
    local exes = {}
    for _, test in ipairs(tests) do
        exes[test.exe] = 1
    end

    for exe, _ in pairs(exes) do
        set_suites_state(cache.test_lists[exe].map)
    end
end

--- @param old_map gtest-telescope.TestMap
--- @param new_map gtest-telescope.TestMap
local copy_suite_states = function(old_map, new_map)
    local new_state_mapping = {
        [TestState.NONE] = TestState.NONE,
        [TestState.SUCCESS] = TestState.OLD_SUCCESS,
        [TestState.FAILURE] = TestState.OLD_FAILURE,
        [TestState.OLD_SUCCESS] = TestState.OLD_SUCCESS,
        [TestState.OLD_FAILURE] = TestState.OLD_FAILURE,
    }

    for suite_name, item in pairs(old_map) do
        local new_item = new_map[suite_name]
        if new_item then
            for test_name, entry in pairs(item.tests) do
                local new_entry = new_item.tests[test_name]
                if new_entry then
                    new_entry.state = new_state_mapping[entry.state]
                end
            end
        end
    end
end

--- @param executables string|string[]
--- @return gtest-telescope.TestEntry[]
local get_test_list = function(executables)
    local _get_test_list = function(exe)
        local mt = get_mtime(vim.fs.joinpath(config.executables_folder, exe))
        local cached = cache.test_lists[exe]

        if cached and (cached.mtime.sec > mt.sec or (cached.mtime.sec == mt.sec and cached.mtime.nsec >= mt.nsec)) then
            set_suites_state(cached.map)
            return cached.tests
        end

        local report = generate_gtest_report(exe)
        if not report then
            return {}
        end

        local list, map = generate_test_list_from_report(report)

        if cached then
            copy_suite_states(cached.map, map)
        end

        local entry = { tests = list, map = map, mtime = mt }
        cache.test_lists[exe] = entry

        set_suites_state(map)
        return list
    end

    if type(executables) == "string" then
        return _get_test_list(executables)
    end

    local test_list = {}
    for _, exe in ipairs(executables) do
        vim.list_extend(test_list, _get_test_list(exe))
    end

    return test_list
end

--- @param executables string[]
--- @param on_choice function(item: string?, idx: integer?)
local select_executable = function(executables, on_choice)
    vim.ui.select(executables, {
        prompt = "Select test executable",
        format_item = function(item)
            return vim.fs.basename(item)
        end,
        telescope = { file_ignore_patterns = false },
    }, on_choice)
end

--- @return Sorter
local get_sorter = function()
    local Sorter = require("telescope.sorters").Sorter

    local cached_rx = {}
    local get_rx = function(input)
        local rx = cached_rx[input]

        if not rx then
            -- replace . with \.
            -- replace * with .*
            local mod_input = string.gsub(input, "%.", "\\.")
            mod_input = string.gsub(mod_input, "*", ".*")

            -- smart case (insensitive if all lower case, sensitive if at least one upper case)
            if not string.find(input, "[A-Z]") then
                mod_input = "\\c" .. mod_input
            else
                mod_input = "\\C" .. mod_input
            end

            rx = vim.regex(mod_input)
            if not rx then
                return
            end

            cached_rx[input] = rx
        end

        return rx
    end

    return Sorter:new({
        -- self
        --- @param prompt string text in the prompt line
        --- @param line string entry.ordinal
        --- @param entry table
        scoring_function = function(_, prompt, line, entry)
            if config._suites_only and entry.value.test_suite then
                return -1
            end

            if #prompt < 2 then
                return 1
            end

            local rx = get_rx(prompt)

            if not rx or rx:match_str(line) then
                return 1
            else
                return -1
            end
        end,
    })
end

--- @param tests gtest-telescope.TestEntry[]
--- @param on_choice function(selection:gtest-telescope.TestEntry[])
--- @param single_selection boolean
local telescope_pick_tests = function(tests, on_choice, single_selection)
    local action_state = require("telescope.actions.state")
    local action_utils = require("telescope.actions.utils")
    local actions = require("telescope.actions")
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")

    local on_choice_wrapped = vim.schedule_wrap(on_choice)

    -- sort alphabetically
    table.sort(tests, function(a, b)
        return a.test_filter < b.test_filter
    end)

    pickers
        .new(config.telescope, {
            prompt_title = "Select Test",
            finder = finders.new_table({
                results = tests,
                entry_maker = function(entry)
                    return {
                        value = entry,
                        display = entry.display_func,
                        ordinal = entry.test_filter,
                        path = entry.path, -- used by edit action
                        lnum = entry.line, -- used by edit action
                    }
                end,
            }),
            sorter = get_sorter(),
            attach_mappings = function(prompt_bufnr, map)
                actions.select_default:replace(function()
                    local current_picker = action_state.get_current_picker(prompt_bufnr)
                    local has_multi_selection = (next(current_picker:get_multi_selection()) ~= nil)
                    local selection = {}

                    if has_multi_selection then
                        action_utils.map_selections(prompt_bufnr, function(entry, _)
                            table.insert(selection, entry)
                        end)
                    else
                        selection = { action_state.get_selected_entry() }
                    end

                    actions.close(prompt_bufnr)

                    local selected_tests = {}
                    for _, item in ipairs(selection) do
                        table.insert(selected_tests, item.value)
                    end

                    cache.picker = current_picker
                    cache.last_run = {
                        on_choice = on_choice_wrapped,
                        tests = selected_tests,
                    }

                    on_choice_wrapped(selected_tests)
                end)

                for key, act in pairs(config.mappings) do
                    map({ "i", "n" }, key, act, {})
                end

                if single_selection then
                    map({ "i", "n" }, "<Tab>", actions.nop, {})
                    map({ "i", "n" }, "<S-Tab>", actions.nop, {})
                end

                return true
            end,
        })
        :find()
end

--- @param tests gtest-telescope.TestEntry[]
--- @return string[]
local build_test_commands = function(tests)
    local test_filters = {}

    for _, test in ipairs(tests) do
        if not test_filters[test.exe] then
            test_filters[test.exe] = {}
        end
        table.insert(test_filters[test.exe], test.test_filter)
    end

    local commands = {}

    for exe, filters in pairs(test_filters) do
        local command = exe .. " --gtest_filter=" .. table.concat(filters, ":")
        table.insert(commands, command)
    end

    return commands
end

--- @param tests gtest-telescope.TestEntry[]
local print_tests = function(tests)
    local commands = build_test_commands(tests)

    print(vim.inspect(tests))
    print(vim.inspect(commands))
end

--- @param tests gtest-telescope.TestEntry[]
local run_tests = function(tests)
    local commands = build_test_commands(tests)

    for _, cmd in ipairs(commands) do
        terminal.exec(cmd, config.executables_folder)
    end
end

--- @param tests gtest-telescope.TestEntry[]
local debug_test = function(tests)
    assert(#tests == 1)

    local test = tests[1]

    local dap_config = {
        program = vim.fs.joinpath(config.executables_folder, test.exe),
        cwd = config.executables_folder,
        args = { "--gtest_filter=" .. test.test_filter },
    }

    dap_config = vim.tbl_deep_extend("keep", dap_config, config.dap_config)

    local enrich_config = {
        type = "cppdbg",
        name = "Launch test: " .. test.test_filter,
        request = "launch",
    }

    dap_config = vim.tbl_deep_extend("keep", dap_config, enrich_config)

    local dap = require("dap")
    dap.run(dap_config)
end

--- @param on_choice function(selection:gtest-telescope.TestEntry[])
--- @param single_selection boolean
local pick_tests_single_exe = function(on_choice, single_selection)
    local executables = find_executables()

    select_executable(executables, function(exe)
        if not exe then
            return
        end

        local test_list = get_test_list(exe)
        if vim.tbl_isempty(test_list) then
            return
        end

        telescope_pick_tests(test_list, on_choice, single_selection)
    end)
end

--- @param on_choice function(selection:gtest-telescope.TestEntry[])
--- @param single_selection boolean
local pick_tests_current_buffer = function(on_choice, single_selection)
    local executables = find_executables()
    local test_list = get_test_list(executables)

    local current_path = vim.api.nvim_buf_get_name(0)

    local test_suites = {}
    local filtered_list = vim.tbl_filter(function(item)
        if item.path ~= current_path then
            return false
        end

        test_suites[item.test_suite] = { exe = item.exe, type_param = item.type_param }
        return true
    end, test_list)

    if vim.tbl_isempty(filtered_list) then
        return
    end

    -- re-add the test suites
    for test_suite, tbl in pairs(test_suites) do
        table.insert(filtered_list, make_entry_for_test_suite(test_suite, tbl.type_param, tbl.exe))
    end

    telescope_pick_tests(filtered_list, on_choice, single_selection)
end

--- @param on_choice function(selection:gtest-telescope.TestEntry[])
--- @param single_selection boolean
local pick_tests_current_line = function(on_choice, single_selection)
    local executables = find_executables()
    local test_list = get_test_list(executables)

    local current_path = vim.api.nvim_buf_get_name(0)
    local current_line, _ = unpack(vim.api.nvim_win_get_cursor(0))

    local test_suites = {}
    local max_line = -1

    -- first select all tests behind the current line in the current buffer
    local filtered_list = vim.tbl_filter(function(item)
        if item.path ~= current_path then
            return false
        end

        if item.line > current_line then
            return false
        end

        if item.line > max_line then
            max_line = item.line
        end

        return true
    end, test_list)

    if vim.tbl_isempty(filtered_list) then
        return
    end

    -- then select the test(s) closest to the current line
    filtered_list = vim.tbl_filter(function(item)
        if item.line ~= max_line then
            return false
        end

        test_suites[item.test_suite] = { exe = item.exe, type_param = item.type_param }
        return true
    end, filtered_list)

    -- re-add the test suites
    for test_suite, tbl in pairs(test_suites) do
        table.insert(filtered_list, make_entry_for_test_suite(test_suite, tbl.type_param, tbl.exe))
    end

    telescope_pick_tests(filtered_list, on_choice, single_selection)
end

local M = {}

--- @param opts table
M.setup = function(opts)
    config.update(opts)
    terminal.setup(config.toggleterm, parse_output_line)

    vim.api.nvim_set_hl(0, "GTestTelescopeSuccess", { link = "DiagnosticOk" })
    vim.api.nvim_set_hl(0, "GTestTelescopeFailure", { link = "DiagnosticError" })
    vim.api.nvim_set_hl(0, "GTestTelescopeOldSuccess", { link = "DiagnosticHint" })
    vim.api.nvim_set_hl(0, "GTestTelescopeOldFailure", { link = "DiagnosticWarn" })
end

M.clear_cache = function()
    cache.test_lists = {}
    cache.picker = nil
    cache.last_run = nil
end

M.run_tests_single_exe = function()
    pick_tests_single_exe(run_tests, false)
end

M.run_tests_current_buffer = function()
    pick_tests_current_buffer(run_tests, false)
end

M.run_tests_current_line = function()
    pick_tests_current_line(run_tests, false)
end

M.debug_test_single_exe = function()
    pick_tests_single_exe(debug_test, true)
end

M.debug_tests_current_buffer = function()
    pick_tests_current_buffer(debug_test, true)
end

M.debug_tests_current_line = function()
    pick_tests_current_line(debug_test, true)
end

M.resume_last = function()
    if not cache.picker then
        return
    end

    -- NOTE: selected items are not highlighted, but ":Telescope resume" does the same
    cache.picker.get_window_options = nil
    set_suites_state_from_list(cache.last_run and cache.last_run.tests or {})
    require("telescope.pickers").new(config.telescope, cache.picker):find()
end

M.run_last = function()
    if not cache.last_run then
        return
    end

    cache.last_run.on_choice(cache.last_run.tests)
end

M.toggle_term = function()
    terminal.toggle_term()
end

M.kill_term = function()
    terminal.kill_term()
end

return M
