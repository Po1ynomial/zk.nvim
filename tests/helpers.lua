local H = {}

function H.new_set(setup)
  local MiniTest = require("mini.test")
  local child = MiniTest.new_child_neovim()
  local workspace
  local T = MiniTest.new_set({
    hooks = {
      pre_case = function()
        local label = table.concat(MiniTest.current.case.desc, "-"):gsub("[^%w_-]", "_")
        local results = vim.fs.joinpath(vim.uv.cwd(), ".test-results")
        vim.fn.mkdir(results, "p")
        workspace = assert(vim.uv.fs_mkdtemp(vim.fs.joinpath(results, label .. "-XXXXXX")))
        child.start({
          "-u",
          "tests/minimal_init.lua",
          "--cmd",
          "let $XDG_STATE_HOME = " .. vim.fn.string(vim.fs.joinpath(workspace, "state")),
        })
        child.lua("require('tests.helpers').workspace = ...", { workspace })
        child.lua("vim.lsp.set_log_level('debug')")
        if setup then
          child.lua(setup)
        end
      end,
      post_case = function()
        -- Stop servers before stopping their editor, even when the test or setup failed.
        local ok, error_message = pcall(
          child.lua,
          [[
          for _, client in ipairs(vim.lsp.get_clients()) do client:stop() end
          if not vim.wait(2000, function() return #vim.lsp.get_clients() == 0 end, 20) then
            for _, client in ipairs(vim.lsp.get_clients()) do client:stop(true) end
            assert(vim.wait(2000, function() return #vim.lsp.get_clients() == 0 end, 20), 'language servers did not stop')
          end
        ]]
        )
        child.stop()
        local failed = #MiniTest.current.case.exec.fails > 0 or not ok
        if failed then
          MiniTest.add_note("failure artifacts: " .. tostring(workspace))
        elseif workspace then
          vim.fn.delete(workspace, "rf")
        end
        assert(ok, error_message)
      end,
    },
  })
  return T, child
end

function H.wait(predicate, message)
  assert(vim.wait(10000, predicate, 20), message or "timed out")
end

function H.system(arguments)
  local result = vim.system(arguments, { text = true }):wait(10000)
  assert(result.code == 0, (result.stderr or "") .. (result.stdout or ""))
  return result
end

function H.write(path, text)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  vim.fn.writefile(vim.split(text, "\n", { plain = true }), path)
end

function H.archive(name, engine)
  local root = vim.fs.joinpath(H.workspace, name or "archive")
  if engine then
    H.system({ assert(vim.env.ZK_BIN, "ZK_BIN is required"), "init", root })
  else
    H.write(vim.fs.joinpath(root, "zk.toml"), "format = 3")
    vim.fn.mkdir(vim.fs.joinpath(root, "zettel"), "p")
  end
  root = assert(vim.uv.fs_realpath(root))
  if engine then
    local library = vim.fs.joinpath(root, "lib/zettel.typ")
    vim.fn.writefile(
      { "#let summary(body) = body", "#let tags(..values) = none", "#let topic = (coding: none,)" },
      library,
      "a"
    )
    H.write(
      vim.fs.joinpath(root, "templates/zettel.typ"),
      [[#import "../lib/zettel.typ": zettel, summary, tags, topic
#show: zettel
= Untitled <new>
// @zk-field "summary" kind=markup
#summary[]
// @zk-field "tags" kind=string-list
#tags()
// @zk-field "topic" kind=string
#topic.coding]]
    )
    H.note(root, "2603231410", "Source note", "Link to @2603231411.")
    H.note(root, "2603231411", "Target note", "No outgoing links.")
    H.note(root, "2603231412", "Removable note", "No outgoing links.")
  end
  return root
end

function H.note(root, id, title, body)
  local path = vim.fs.joinpath(root, "zettel", id .. ".typ")
  H.write(
    path,
    string.format(
      [[#import "../lib/zettel.typ": zettel, summary, tags, topic
#show: zettel
= %s <%s>
#summary[Note summary.]
#tags("saved")
#topic.coding
%s]],
      title,
      id,
      body or ""
    )
  )
  return path
end

function H.setup(root)
  local binary = assert(vim.env.ZK_BIN, "ZK_BIN is required")
  require("zk").setup({
    archive = root,
    lsp_cmd = { binary, "lsp" },
    cli_cmd = { binary },
    debounce_ms = 10,
  })
end

function H.client(root)
  local found
  H.wait(function()
    found = vim.iter(vim.lsp.get_clients({ name = "zk" })):find(function(client)
      return client.root_dir == root and client.initialized and client.config.zk_protocol
    end)
    return found ~= nil
  end, "zk client did not initialize for " .. root)
  return found
end

function H.open(root, id)
  local path = vim.fs.joinpath(root, "zettel", (id or "2603231410") .. ".typ")
  vim.cmd("hide edit " .. vim.fn.fnameescape(path))
  local bufnr = vim.api.nvim_get_current_buf()
  local client = H.client(root)
  H.wait(function()
    return vim.lsp.buf_is_attached(bufnr, client.id)
  end, "zk did not attach to note")
  return bufnr, client
end

function H.request(client, method, params, bufnr)
  local response, err =
    client:request_sync(method, params, 2000, bufnr or vim.api.nvim_get_current_buf())
  assert(response and not response.err, vim.inspect(err or response))
  return response.result
end

function H.query(client, command, id)
  return assert(
    require("zk.protocol").unwrap(
      H.request(client, "workspace/executeCommand", { command = command, arguments = { id } })
    )
  )
end

function H.callback(invoke)
  local result
  invoke(function(value)
    result = value
  end)
  H.wait(function()
    return result ~= nil
  end, "CLI operation did not complete")
  return result
end

function H.replace(bufnr, old, new)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)) do
    if line == old then
      vim.api.nvim_buf_set_lines(bufnr, row - 1, row, true, { new })
      return row
    end
  end
  error("source line not found: " .. old)
end

return H
