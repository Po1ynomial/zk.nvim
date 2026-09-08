local repo = assert(vim.env.ZK_REPO, "ZK_REPO")
local binary = assert(vim.env.ZK_BIN, "ZK_BIN")
local personal = assert(vim.uv.fs_realpath(vim.env.ZK_PERSONAL_ARCHIVE))
local local_archive = assert(vim.uv.fs_realpath(vim.env.ZK_LOCAL_ARCHIVE))
local alternate = assert(vim.uv.fs_realpath(vim.env.ZK_ALTERNATE_ARCHIVE))
local invalid = assert(vim.uv.fs_realpath(vim.env.ZK_INVALID_ARCHIVE))
local missing = assert(vim.env.ZK_MISSING_ARCHIVE)
local report_path = assert(vim.env.ZK_FALLBACK_REPORT, "ZK_FALLBACK_REPORT")
local unrelated_path = vim.fs.joinpath(vim.fs.dirname(personal), "unrelated.txt")
local local_context_path = vim.fs.joinpath(local_archive, "assets/context.txt")

local function client_for_root(root)
  return vim.iter(vim.lsp.get_clients({ name = "zk" })):find(function(client)
    return client.root_dir and vim.uv.fs_realpath(client.root_dir) == root
  end)
end

local function wait_for_client(root)
  assert(
    vim.wait(10000, function()
      local client = client_for_root(root)
      return client and client.initialized
    end, 20),
    "zk lsp did not start for " .. root
  )
  return assert(client_for_root(root))
end

vim.opt.runtimepath:prepend(repo)
vim.cmd("filetype plugin on")
vim.cmd.edit(vim.fn.fnameescape(unrelated_path))
local unrelated_buf = vim.api.nvim_get_current_buf()

local zk = require("zk")
zk.setup({
  archive = "$ZK_PERSONAL_ARCHIVE",
  lsp_cmd = { binary, "lsp" },
  cli_cmd = { binary },
  debounce_ms = 10,
})

assert(vim.fn.exists(":ZkSetArchive") == 2, "ZkSetArchive is missing")
local personal_client = wait_for_client(personal)
assert(zk.archive == personal, "configured archive is not exposed as session state")
assert(vim.tbl_isempty(personal_client.attached_buffers), "fallback client started attached")

local selected
vim.ui.select = function(items, _, callback)
  selected = items[1]
  callback(items[1])
end
zk.find("Personal note")
assert(
  vim.wait(5000, function()
    return selected ~= nil
      and vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0))
        == vim.fs.joinpath(personal, "zettel/2603231500.typ")
  end, 20),
  "global search did not use the configured fallback"
)
local personal_buf = vim.api.nvim_get_current_buf()
assert(
  vim.wait(5000, function()
    return vim.lsp.buf_is_attached(personal_buf, personal_client.id)
  end, 20),
  "fallback Zettel did not attach to the eager client"
)

local keyword_line
for index, line in ipairs(vim.api.nvim_buf_get_lines(personal_buf, 0, -1, true)) do
  if line == '#keywords("personal")' then
    keyword_line = index - 1
    break
  end
end
assert(keyword_line, "personal keyword line not found")
vim.api.nvim_buf_set_lines(
  personal_buf,
  keyword_line,
  keyword_line + 1,
  true,
  { "#keywords(computed)" }
)
local diagnostic_namespace = vim.lsp.diagnostic.get_namespace(personal_client.id)
assert(
  vim.wait(5000, function()
    return vim
      .iter(vim.diagnostic.get(personal_buf, { namespace = diagnostic_namespace }))
      :any(function(item)
        return item.code == "metadata.keywords"
      end)
  end, 20),
  "personal diagnostic did not arrive"
)

vim.api.nvim_set_current_buf(unrelated_buf)
zk.diagnostics()
assert(
  vim.wait(5000, function()
    return vim.iter(vim.fn.getqflist()):any(function(item)
      return item.text:find("keywords", 1, true) ~= nil
    end)
  end, 20),
  "global diagnostics did not use the fallback client"
)
vim.cmd.cclose()
vim.api.nvim_set_current_buf(unrelated_buf)

local checked
zk.check(function(result)
  checked = result
end)
assert(vim.wait(5000, function()
  return checked ~= nil
end, 20) and checked.code == 0, "global check did not use the configured fallback")

local removed
zk.remove("2603231501", function(result)
  removed = result
end)
assert(vim.wait(5000, function()
  return removed ~= nil
end, 20) and removed.code == 0, "global explicit removal did not use the configured fallback")
assert(not vim.uv.fs_stat(vim.fs.joinpath(personal, "zettel/2603231501.typ")))

local created
zk.new(function(result)
  created = result
end)
assert(vim.wait(5000, function()
  return created ~= nil
end, 20) and created.code == 0, "global creation did not use the configured fallback")
assert(vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)):sub(1, #personal) == personal)

local local_path = vim.fs.joinpath(local_archive, "zettel/2603231500.typ")
vim.cmd.edit(vim.fn.fnameescape(local_context_path))
selected = nil
zk.find("Local note")
assert(
  vim.wait(5000, function()
    return selected ~= nil and vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0)) == local_path
  end, 20),
  "local archive did not take precedence over the fallback"
)
local local_client = wait_for_client(local_archive)
assert(
  vim.lsp.buf_is_attached(vim.api.nvim_get_current_buf(), local_client.id),
  "local search target did not attach to its on-demand client"
)

vim.api.nvim_set_current_buf(unrelated_buf)
pcall(vim.cmd, "ZkSetArchive " .. vim.fn.fnameescape(missing))
assert(zk.archive == personal, "invalid switch replaced the fallback")
assert(client_for_root(personal).id == personal_client.id, "invalid switch replaced the client")

pcall(vim.cmd, "ZkSetArchive " .. vim.fn.fnameescape(invalid))
vim.wait(500, function()
  return false
end, 20)
assert(zk.archive == personal, "failed server initialization replaced the fallback")
assert(client_for_root(invalid) == nil, "failed server client is still running")
assert(
  client_for_root(personal).id == personal_client.id,
  "failed server initialization replaced the client"
)

vim.cmd("ZkSetArchive " .. vim.fn.fnameescape(alternate))
assert(
  vim.wait(10000, function()
    return zk.archive == alternate
      and client_for_root(alternate)
      and client_for_root(alternate).initialized
  end, 20),
  "valid switch did not replace the fallback"
)
assert(client_for_root(personal), "client serving an open previous-fallback buffer was stopped")
assert(client_for_root(local_archive).id == local_client.id, "local archive client was replaced")

selected = nil
zk.find("Alternate note")
assert(
  vim.wait(5000, function()
    return selected ~= nil
      and vim.uv.fs_realpath(vim.api.nvim_buf_get_name(0))
        == vim.fs.joinpath(alternate, "zettel/2603231500.typ")
  end, 20),
  "global search did not use the switched fallback"
)

vim.fn.writefile({
  vim.json.encode({
    eagerStartup = true,
    readableState = true,
    globalSearch = true,
    fallbackAttachment = true,
    globalCli = true,
    globalDiagnostics = true,
    localPrecedence = true,
    invalidSwitchPreserved = true,
    successfulSwitch = true,
    previousLocalClientPreserved = true,
  }),
}, report_path)

for _, client in ipairs(vim.lsp.get_clients()) do
  if client.name == "zk" then
    client:stop(true)
  end
end
vim.cmd.qa({ bang = true })
