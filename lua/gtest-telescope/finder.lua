local scheduler = require("plenary.async").util.scheduler

-- copied from telescope.finders.new_table
return function(opts)
    local results = {}
    for k, v in ipairs(opts.results) do
        local entry = opts.entry_maker(v)

        if entry then
            entry.index = k
            table.insert(results, entry)
        end
    end

    return setmetatable({
        results = results,
        entry_maker = opts.entry_maker,
        close = function() end,
    }, {
        __call = function(_, _, process_result, process_complete)
            for i, v in ipairs(results) do
                if process_result(v) then
                    break
                end

                if i % 1000 == 0 then
                    scheduler()
                end
            end

            process_complete()

            if opts.callback then
                opts.callback()
            end
        end,
    })
end
