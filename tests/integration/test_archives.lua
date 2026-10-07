local H = require("tests.helpers")
local T, child = H.new_set()

T["fallback starts eagerly and global commands work from unrelated buffers"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local root = H.archive('personal', true)
    vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(H.workspace, 'unrelated.txt')))
    local unrelated = vim.api.nvim_get_current_buf()
    vim.env.ZK_PERSONAL_ARCHIVE = root
    require('zk').setup({ archive = '$ZK_PERSONAL_ARCHIVE', lsp_cmd = { vim.env.ZK_BIN, 'lsp' }, cli_cmd = { vim.env.ZK_BIN } })
    local client = H.client(root)
    local zk = require('zk')
    assert(zk.archive == root and vim.tbl_isempty(client.attached_buffers))
    vim.ui.select = function(items, _, callback) callback(items[1]) end
    zk.find('Source note')
    H.wait(function() return vim.api.nvim_buf_get_name(0) == vim.fs.joinpath(root, 'zettel/2603231410.typ') end)
    local source = vim.api.nvim_get_current_buf()
    H.wait(function() return vim.lsp.buf_is_attached(source, client.id) end)
    H.replace(source, '#tags("saved")', '#tags(computed)')
    local namespace = vim.lsp.diagnostic.get_namespace(client.id)
    H.wait(function() return #vim.diagnostic.get(source, { namespace = namespace }) > 0 end)
    vim.api.nvim_set_current_buf(unrelated)
    zk.diagnostics()
    assert(vim.fn.getqflist()[1].text:find('[tags]', 1, true))
    vim.cmd.cclose()
    vim.api.nvim_set_current_buf(unrelated)
    assert(H.callback(zk.check).code == 0)
    assert(zk.remove('2603231412') == nil)
    vim.bo[source].modified = false
    assert(H.callback(function(callback) zk.remove('2603231412', callback) end).code == 0)
    assert(H.callback(zk.new).code == 0)
    assert(vim.api.nvim_buf_get_name(0):sub(1, #root) == root)
  ]])
end

T["nearest local archive wins over the fallback even from a non-note buffer"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local fallback = H.archive('personal', true)
    local root = H.archive('local', true)
    H.note(root, '2603231410', 'Local note')
    H.setup(fallback)
    H.client(fallback)
    vim.cmd.edit(vim.fn.fnameescape(vim.fs.joinpath(root, 'assets/context.txt')))
    vim.ui.select = function(items, _, callback) callback(items[1]) end
    require('zk').find('Local note')
    H.wait(function() return vim.api.nvim_buf_get_name(0) == vim.fs.joinpath(root, 'zettel/2603231410.typ') end)
    local client = H.client(root)
    H.wait(function() return vim.lsp.buf_is_attached(0, client.id) end)
    assert(require('zk').archive == fallback)
  ]])
end

T["invalid archive switches preserve the selected fallback"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local root = H.archive('personal', true)
    local invalid = H.archive('invalid', true)
    H.write(vim.fs.joinpath(invalid, 'zk.toml'), 'format = 2')
    H.setup(root)
    local client = H.client(root)
    local zk = require('zk')
    zk.set_archive(vim.fs.joinpath(H.workspace, 'missing'))
    assert(zk.archive == root)
    local failed
    vim.notify = function(message) if message:find('exited before initialization', 1, true) then failed = true end end
    zk.set_archive(invalid)
    H.wait(function() return failed end, 'invalid archive did not report startup failure')
    assert(zk.archive == root and H.client(root).id == client.id)
    H.wait(function() return vim.iter(vim.lsp.get_clients({ name = 'zk' })):all(function(item) return item.root_dir ~= invalid end) end)
  ]])
end

T["switching fallback preserves clients serving open archives"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local personal, root, alternate = H.archive('personal', true), H.archive('local', true), H.archive('alternate', true)
    H.note(alternate, '2603231410', 'Alternate note')
    H.setup(personal)
    local _, personal_client = H.open(personal)
    local _, local_client = H.open(root)
    vim.cmd('hide edit ' .. vim.fn.fnameescape(vim.fs.joinpath(H.workspace, 'unrelated.txt')))
    require('zk').set_archive(alternate)
    H.wait(function() return require('zk').archive == alternate end)
    assert(H.client(personal).id == personal_client.id and H.client(root).id == local_client.id)
    vim.ui.select = function(items, _, callback) callback(items[1]) end
    require('zk').find('Alternate note')
    H.wait(function() return vim.api.nvim_buf_get_name(0) == vim.fs.joinpath(alternate, 'zettel/2603231410.typ') end)
  ]])
end

T["switching fallback stops unused clients and does not require a presentation library"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local root, alternate = H.archive('personal', true), H.archive('alternate', true)
    vim.fn.delete(vim.fs.joinpath(alternate, 'lib/zettel.typ'))
    H.setup(root)
    local old = H.client(root).id
    require('zk').set_archive(alternate)
    H.wait(function() return require('zk').archive == alternate end)
    H.wait(function()
      local previous = vim.lsp.get_client_by_id(old)
      return previous == nil or previous:is_stopped()
    end, 'unused fallback client was not stopped')
  ]])
end

return T
