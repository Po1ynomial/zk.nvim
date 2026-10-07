local H = require("tests.helpers")
local T, child = H.new_set()

T["Tinymist and ZK share the archive root and handle references without unknown labels"] = function()
  child.lua([[
    local H = require('tests.helpers')
    local root = H.archive('archive', true)
    -- A control label ensures the assertion observes completed Typst diagnostics, not silence.
    H.note(root, '2603231410', 'Source note', 'Link to @2603231411 and @test_missing_label.')
    local runtime = vim.fs.joinpath(H.workspace, 'tinymist-runtime')
    H.write(vim.fs.joinpath(runtime, 'lsp/tinymist.lua'), "return { cmd = { vim.env.TINYMIST_BIN, 'lsp' }, filetypes = { 'typst' }, root_markers = { '.git' } }")
    vim.opt.runtimepath:prepend(runtime)
    local published = {}
    local handler = vim.lsp.handlers['textDocument/publishDiagnostics']
    vim.lsp.handlers['textDocument/publishDiagnostics'] = function(err, params, context, config)
      local client = vim.lsp.get_client_by_id(context.client_id)
      if client and client.name == 'tinymist' then published[params.uri] = params.diagnostics end
      return handler(err, params, context, config)
    end
    vim.lsp.enable('tinymist')
    H.setup()
    local bufnr, client = H.open(root)
    local tinymist
    H.wait(function()
      tinymist = vim.lsp.get_clients({ bufnr = bufnr, name = 'tinymist' })[1]
      return tinymist and tinymist.initialized
    end, 'Tinymist did not initialize')
    assert(vim.uv.fs_realpath(tinymist.root_dir) == root, 'zk.toml did not select the Tinymist root')
    assert(vim.lsp.buf_is_attached(bufnr, client.id))
    local uri = vim.uri_from_bufnr(bufnr)
    H.wait(function() return published[uri] ~= nil end, 'Tinymist did not publish diagnostics')
    assert(vim.iter(published[uri]):any(function(diagnostic)
      return diagnostic.message:find('test_missing_label', 1, true) ~= nil
    end), 'control label did not produce a diagnostic')
    for _, diagnostic in ipairs(published[uri]) do
      assert(not diagnostic.message:find('2603231411', 1, true), diagnostic.message)
    end
    assert(not client.config.zk_protocol.features.categoryCompletion)
  ]])
end

return T
