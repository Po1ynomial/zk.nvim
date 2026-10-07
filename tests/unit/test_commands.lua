local H = require("tests.helpers")
local T, child = H.new_set()

T["setup registers commands and can disable mappings"] = function()
  child.lua([[
    local zk = require('zk')
    zk.setup({ mappings = false })
    for _, name in ipairs({ 'ZkFind', 'ZkBacklinks', 'ZkDiagnostics', 'ZkCheck', 'ZkNew', 'ZkRemove', 'ZkRefresh', 'ZkSetArchive' }) do
      assert(vim.fn.exists(':' .. name) == 2, name .. ' missing')
    end
    assert(zk.is_configured())
  ]])
end

T["saved checks use disk byte ranges, field names, and unknown-code severity"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local root = H.archive()
    local path = vim.fs.joinpath(root, 'zettel/2603231410.typ')
    local title, prefix = '= Saved note <2603231410>', 'λ😀 '
    H.write(path, title .. '\n' .. prefix .. '@9999999999.')
    vim.cmd.edit(vim.fn.fnameescape(path))
    vim.api.nvim_buf_set_lines(0, 0, 0, true, { 'Unsaved text shifts buffer positions, not saved ranges.' })
    local diagnostic = { path = 'zettel/2603231410.typ', code = 'future.problem', severity = 'warning',
      message = 'Future problem', field = 'custom field', range = { start = #title + 1 + #prefix, ['end'] = #title + 12 + #prefix } }
    vim.system = function(command, options, callback)
      assert(vim.deep_equal(command, { 'zk', '--archive', root, 'check', '--format', 'json' }))
      assert(options.cwd == root)
      callback({ code = 0, stdout = vim.json.encode({ schema_version = 2, data = { diagnostic } }), stderr = '' })
      return {}
    end
    local result = H.callback(require('zk').check)
    assert(result.code == 0)
    local item = vim.fn.getqflist()[1]
    assert(item.type == 'W' and item.lnum == 2 and item.col == #prefix + 1)
    assert(item.text:find('future.problem [custom field]', 1, true))
  ]])
end

T["completed integrity checks with exit status 1 populate quickfix"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local root = H.archive()
    vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(root, 'context.txt')))
    vim.system = function(_, _, callback)
      callback({ code = 1, stdout = vim.json.encode({ schema_version = 2, data = {
        { path = 'zettel/2603231410.typ', code = 'future.error', severity = 'error', message = 'Problem', field = vim.NIL, range = vim.NIL },
      } }), stderr = '' })
      return {}
    end
    assert(H.callback(require('zk').check).code == 1)
    assert(vim.fn.getqflist()[1].type == 'E')
  ]])
end

T["invalid JSON and operational failures preserve useful quickfix entries"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local root = H.archive()
    local bufnr = vim.fn.bufadd(vim.fs.joinpath(root, 'context.txt'))
    vim.api.nvim_set_current_buf(bufnr)
    vim.fn.setqflist({ { text = 'Previous useful result', valid = 1 } })
    local notifications = {}
    vim.notify = function(message) table.insert(notifications, message) end
    for _, result in ipairs({
      { code = 0, stdout = vim.json.encode({ schema_version = 3, data = {} }), stderr = '' },
      { code = 1, stdout = '{"schema_version":2,"data":[', stderr = '' },
      { code = 1, stdout = '', stderr = 'archive could not be read' },
      { code = 0, stdout = vim.json.encode({ schema_version = 2, data = { unexpected = true } }), stderr = '' },
    }) do
      vim.system = function(_, _, callback) callback(result); return {} end
      local count = #notifications
      H.callback(require('zk').check)
      assert(#notifications == count + 1, 'invalid output was not reported')
      assert(vim.fn.getqflist()[1].text == 'Previous useful result')
    end
  ]])
end

T["removal refuses modified notes elsewhere in the selected archive"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local root = H.archive()
    local source = vim.fs.joinpath(root, 'zettel/2603231410.typ')
    H.write(source, '= Source <2603231410>')
    vim.cmd.edit(vim.fn.fnameescape(source))
    vim.api.nvim_buf_set_lines(0, -1, -1, true, { '@2603231411' })
    vim.system = function() error('modified archive reached the saved-state CLI') end
    assert(require('zk').remove('2603231411') == nil)
  ]])
end

return T
