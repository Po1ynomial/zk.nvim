local H = require("tests.helpers")
local T, child = H.new_set([[
  local H = require('tests.helpers')
  H.root = H.archive('archive', true)
  H.setup()
  H.bufnr, H.server = H.open(H.root)
]])

T["attaches protocol-2 clients with generic metadata and default mappings"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local descriptor = H.server.config.zk_protocol
    assert(descriptor.version == 2 and descriptor.data_schema_version == 2)
    local node = H.query(H.server, 'zk.queryNode', '2603231410')
    assert(node.metadata.tags.kind == 'string-list' and node.metadata.tags.value[1] == 'saved')
    assert(node.metadata.summary.kind == 'markup' and node.metadata.topic.value == 'coding')
    assert(node.abstract == nil and node.keywords == nil and node.category == nil)
    local mapping = vim.fn.maparg('gd', 'n', false, true)
    assert(mapping.buffer == 1 and type(mapping.callback) == 'function')
  ]])
end

T["optional features gate custom requests and decorations"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local zk = require('zk')
    local features = H.server.config.zk_protocol.features
    features.referenceTitleDecorations = false
    zk.refresh(H.bufnr)
    assert(#vim.api.nvim_buf_get_extmarks(H.bufnr, zk.namespace, 0, -1, {}) == 0)
    features.referenceTitleDecorations = true
    features.archiveQueries = false
    H.server.request = function() error('disabled archive queries sent a request') end
    zk.refresh(H.bufnr)
    zk.backlinks()
  ]])
end

T["decorations conceal UTF-8 spans and fall back for null titles"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local zk = require('zk')
    H.replace(H.bufnr, 'Link to @2603231411.', 'λ😀 Link to @2603231411.')
    H.wait(function()
      return H.query(H.server, 'zk.links', '2603231410')[1].spans[1].start > 0
        and table.concat(vim.api.nvim_buf_get_lines(H.bufnr, 0, -1, true), '\n'):find('λ😀', 1, true)
    end)
    zk.refresh(H.bufnr)
    local function mark(title)
      local marks = vim.api.nvim_buf_get_extmarks(H.bufnr, zk.namespace, 0, -1, { details = true })
      return marks[1] and marks[1][4].virt_text[1][1] == title and marks[1] or nil
    end
    H.wait(function() return mark('Target note') ~= nil end, 'title decoration missing')
    local current = mark('Target note')
    assert(current[3] == #'λ😀 Link to ')
    assert(current[4].conceal == '' and current[4].virt_text_pos == 'inline')
    assert(current[4].end_col == current[3] + 11)
    local target = vim.fs.joinpath(H.root, 'zettel/2603231411.typ')
    H.write(target, 'No title is recoverable.')
    H.wait(function() return H.query(H.server, 'zk.queryNode', '2603231411').title == vim.NIL end)
    zk.refresh(H.bufnr)
    H.wait(function() return mark('2603231411') ~= nil end, 'null title did not fall back to ID')
  ]])
end

T["metadata diagnostics identify fields and clear after repairs"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local zk = require('zk')
    H.replace(H.bufnr, '#tags("saved")', '#tags(computed)')
    local namespace = vim.lsp.diagnostic.get_namespace(H.server.id)
    H.wait(function()
      return vim.iter(vim.diagnostic.get(H.bufnr, { namespace = namespace })):any(function(item)
        return item.code == 'metadata.invalid_shape' and item.user_data.lsp.data.field == 'tags'
      end)
    end, 'metadata diagnostic missing')
    zk.diagnostics()
    assert(vim.iter(vim.fn.getqflist()):any(function(item) return item.text:find('[tags]', 1, true) end))
    vim.cmd.cclose()
    H.replace(H.bufnr, '#tags(computed)', '#tags("saved")')
    H.wait(function()
      return #vim.diagnostic.get(H.bufnr, { namespace = namespace }) == 0
    end, 'repaired metadata diagnostic did not clear')
  ]])
end

T["definition and search preserve the invocation window and modified buffers"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local zk = require('zk')
    local row = H.replace(H.bufnr, 'Link to @2603231411.', 'λ😀 Link to @2603231411.')
    H.wait(function()
      local node = H.request(H.server, 'textDocument/definition', {
        textDocument = { uri = vim.uri_from_bufnr(H.bufnr) }, position = { line = row - 1, character = #'λ😀 Link to @' },
      })
      return node ~= vim.NIL
    end)
    vim.api.nvim_win_set_cursor(0, { row, #'λ😀 Link to @' })
    local window, count = vim.api.nvim_get_current_win(), #vim.api.nvim_list_wins()
    zk.definition()
    H.wait(function() return vim.api.nvim_buf_get_name(0):find('2603231411.typ', 1, true) end)
    assert(vim.api.nvim_get_current_win() == window and #vim.api.nvim_list_wins() == count)
    assert(vim.api.nvim_buf_is_loaded(H.bufnr) and vim.bo[H.bufnr].modified)
    local target = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(target, -1, -1, true, { 'Unsaved target changes.' })
    vim.ui.select = function(items, _, callback) callback(items[1]) end
    zk.find('Source note')
    H.wait(function() return vim.api.nvim_get_current_buf() == H.bufnr end)
    assert(vim.api.nvim_get_current_win() == window and #vim.api.nvim_list_wins() == count)
    assert(vim.api.nvim_buf_is_loaded(target) and vim.bo[target].modified)
  ]])
end

T["backlinks populate quickfix with live authored occurrences"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local target = H.open(H.root, '2603231411')
    require('zk').backlinks()
    H.wait(function() return #vim.fn.getqflist() == 1 end)
    local item = vim.fn.getqflist()[1]
    assert(vim.api.nvim_buf_get_name(item.bufnr) == vim.fs.joinpath(H.root, 'zettel/2603231410.typ'))
    assert(item.lnum == 7 and item.col == #'Link to ' + 1)
    assert(vim.api.nvim_buf_is_valid(target))
  ]])
end

T["creation uses saved templates and preserves unsaved prior buffers"] = function()
  child.lua([[
    local H = require('tests.helpers')
    vim.api.nvim_buf_set_lines(H.bufnr, -1, -1, true, { 'Unsaved before creation.' })
    local window, count = vim.api.nvim_get_current_win(), #vim.api.nvim_list_wins()
    assert(H.callback(require('zk').new).code == 0)
    assert(vim.api.nvim_get_current_win() == window and #vim.api.nvim_list_wins() == count)
    assert(vim.api.nvim_buf_is_loaded(H.bufnr) and vim.bo[H.bufnr].modified)
    local path = vim.api.nvim_buf_get_name(0)
    assert(vim.uv.fs_stat(path))
    local id = vim.fs.basename(path):sub(1, 10)
    local node = H.query(H.server, 'zk.queryNode', id)
    assert(node.metadata.summary.value.text == '' and #node.metadata.tags.value == 0)
    assert(not table.concat(vim.fn.readfile(path), '\n'):find('@zk-field', 1, true))
  ]])
end

T["removal respects saved references and modified notes"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local zk = require('zk')
    local blocked = H.callback(function(callback) zk.remove('2603231411', callback) end)
    assert(blocked.code == 1 and vim.uv.fs_stat(vim.fs.joinpath(H.root, 'zettel/2603231411.typ')))
    vim.api.nvim_buf_set_lines(H.bufnr, -1, -1, true, { 'Unsaved incoming @2603231412.' })
    assert(zk.remove('2603231412') == nil)
    vim.bo[H.bufnr].modified = false
    local target = H.open(H.root, '2603231412')
    vim.api.nvim_buf_set_lines(target, -1, -1, true, { 'Unsaved target.' })
    assert(zk.remove('2603231412') == nil)
    vim.bo[target].modified = false
    assert(H.callback(function(callback) zk.remove('2603231412', callback) end).code == 0)
    assert(not vim.uv.fs_stat(vim.fs.joinpath(H.root, 'zettel/2603231412.typ')))
  ]])
end

T["removal retains target changes made while the CLI is running"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local target = H.open(H.root, '2603231412')
    local result
    require('zk').remove('2603231412', function(value) result = value end)
    vim.api.nvim_buf_set_lines(target, -1, -1, true, { 'Changes during removal.' })
    H.wait(function() return result ~= nil end)
    assert(result.code == 0 and not vim.uv.fs_stat(vim.fs.joinpath(H.root, 'zettel/2603231412.typ')))
    assert(vim.api.nvim_buf_is_loaded(target) and vim.bo[target].modified)
  ]])
end

return T
