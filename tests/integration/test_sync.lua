local H = require("tests.helpers")
local T, child = H.new_set([[
  local H = require('tests.helpers')
  H.root = H.archive('archive', true)
  H.setup()
  H.bufnr, H.server = H.open(H.root)
]])

T["live metadata search includes overlays while CLI search reads saved state"] = function()
  child.lua([[
    local H = require('tests.helpers')
    H.replace(H.bufnr, '#tags("saved")', '#tags("UnsavedOnlyMetadata")')
    H.wait(function() return H.query(H.server, 'zk.queryNode', '2603231410').metadata.tags.value[1] == 'UnsavedOnlyMetadata' end)
    assert(#H.request(H.server, 'workspace/symbol', { query = 'UnsavedOnlyMetadata' }) == 1)
    local result = H.system({ vim.env.ZK_BIN, '--archive', H.root, 'query', 'search', 'UnsavedOnlyMetadata' })
    assert(#assert(require('zk.protocol').unwrap(vim.json.decode(result.stdout))) == 0)
    assert(H.callback(require('zk').check).code == 0)
  ]])
end

T["external create, change, and delete events refresh closed notes"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local path = H.note(H.root, '2603231413', 'External note')
    H.wait(function() return #H.request(H.server, 'workspace/symbol', { query = 'External note' }) == 1 end, 'creation was not watched')
    H.note(H.root, '2603231413', 'Changed external note')
    H.wait(function() return H.query(H.server, 'zk.queryNode', '2603231413').title.text == 'Changed external note' end, 'change was not watched')
    vim.fn.delete(path)
    H.wait(function()
      local response = H.server:request_sync('workspace/symbol', { query = 'Changed external note' }, 2000)
      -- Until the delete event is processed, the old symbol may still require a now-missing file.
      return response and not response.err and #response.result == 0
    end, 'deletion was not watched')
  ]])
end

T["saved template edits re-extract overlays and removing declarations disables fields"] = function()
  child.lua([[
    local H = require('tests.helpers')
    H.replace(H.bufnr, '#tags("saved")', '#tags("UnsavedOnlyMetadata")')
    H.wait(function() return H.query(H.server, 'zk.queryNode', '2603231410').metadata.tags.value[1] == 'UnsavedOnlyMetadata' end)
    local path = vim.fs.joinpath(H.root, 'templates/zettel.typ')
    vim.cmd('hide edit ' .. vim.fn.fnameescape(path))
    assert(#vim.lsp.get_clients({ bufnr = 0, name = 'zk' }) == 0)
    H.replace(0, '// @zk-field "tags" kind=string-list', '// @zk-field "labels" kind=string-list')
    assert(H.query(H.server, 'zk.queryNode', '2603231410').metadata.tags)
    vim.cmd.write()
    H.wait(function()
      local metadata = H.query(H.server, 'zk.queryNode', '2603231410').metadata
      return metadata.tags == nil and metadata.labels and metadata.labels.value[1] == 'UnsavedOnlyMetadata'
    end, 'saved schema did not re-extract the overlay')
    H.replace(0, '// @zk-field "labels" kind=string-list', '// Ordinary comment disables tracking.')
    vim.cmd.write()
    H.wait(function() return H.query(H.server, 'zk.queryNode', '2603231410').metadata.labels == nil end)
  ]])
end

T["failed schema reloads report visible errors and retain the last valid view"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local path = vim.fs.joinpath(H.root, 'templates/zettel.typ')
    local original = table.concat(vim.fn.readfile(path), '\n')
    local visible_error
    vim.lsp.handlers['window/showMessage'] = function(_, params)
      if params.type == vim.lsp.protocol.MessageType.Error then visible_error = params.message end
    end
    H.write(path, '= Invalid template\n// @zk-field "bad" kind=unsupported\n#bad[]')
    H.wait(function() return visible_error ~= nil end, 'failed reload was not visibly reported')
    assert(H.query(H.server, 'zk.queryNode', '2603231410').metadata.tags.value[1] == 'saved')
    H.write(path, original:gsub('@zk%-field "tags"', '@zk-field "labels"'))
    H.wait(function() return H.query(H.server, 'zk.queryNode', '2603231410').metadata.labels ~= nil end, 'reload did not recover')
  ]])
end

T["saved integrity errors return JSON with exit status 1 and Unicode quickfix positions"] = function()
  child.lua([[
    local H = require('tests.helpers')
    H.write(vim.fs.joinpath(H.root, 'zettel/2603231414.typ'), '= Broken <2603231414>\nλ😀 @9999999999.')
    assert(H.callback(require('zk').check).code == 1)
    assert(vim.iter(vim.fn.getqflist()):any(function(item)
      return item.type == 'E' and item.text:find('reference.dangling', 1, true) and item.lnum == 2 and item.col == #'λ😀 ' + 1
    end))
  ]])
end

return T
