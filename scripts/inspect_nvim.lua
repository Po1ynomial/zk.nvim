local repo = assert(vim.env.ZK_REPO, "ZK_REPO")
local archive_env = assert(vim.env.ZK_ARCHIVE, "ZK_ARCHIVE")
local archive = assert(vim.uv.fs_realpath(archive_env))
local binary = assert(vim.env.ZK_BIN, "ZK_BIN")
local tinymist_runtime = assert(vim.env.ZK_TINYMIST_RUNTIME, "ZK_TINYMIST_RUNTIME")
local report_path = assert(vim.env.ZK_REPORT, "ZK_REPORT")
local source_path = vim.fs.joinpath(archive, "zettel/2603231410.typ")
local target_path = vim.fs.joinpath(archive, "zettel/2603231411.typ")
local removable_path = vim.fs.joinpath(archive, "zettel/2603231412.typ")

vim.opt.runtimepath:prepend(tinymist_runtime)
vim.opt.runtimepath:prepend(repo)
vim.opt.runtimepath:append(vim.fs.joinpath(repo, "after"))
vim.cmd("filetype plugin on")
vim.lsp.enable("tinymist")
local zk = require("zk")
zk.setup({
  lsp_cmd = { binary, "lsp" },
  cli_cmd = { binary },
  debounce_ms = 10,
})

for _, command in ipairs({
  "ZkFind",
  "ZkBacklinks",
  "ZkDiagnostics",
  "ZkCheck",
  "ZkNew",
  "ZkRemove",
  "ZkRefresh",
}) do
  assert(vim.fn.exists(":" .. command) == 2, command .. " is missing")
end

vim.cmd.edit(vim.fn.fnameescape(source_path))
vim.bo.filetype = "typst"
local source_buf = vim.api.nvim_get_current_buf()
assert(
  vim.wait(5000, function()
    return #vim.lsp.get_clients({ bufnr = source_buf, name = "zk" }) == 1
  end, 20),
  "zk lsp did not attach"
)
local client = vim.lsp.get_clients({ bufnr = source_buf, name = "zk" })[1]
assert(client)
local definition_mapping = vim.fn.maparg("gd", "n", false, true)
assert(definition_mapping.buffer == 1 and type(definition_mapping.callback) == "function")
assert(
  vim.wait(10000, function()
    local clients = vim.lsp.get_clients({ bufnr = source_buf })
    return vim.iter(clients):any(function(item)
      return item.name == "zk"
    end) and vim.iter(clients):any(function(item)
      return item.name == "tinymist" and item.initialized
    end)
  end, 20),
  "zk and Tinymist did not attach together"
)
local tinymist_client = assert(vim.lsp.get_clients({ bufnr = source_buf, name = "tinymist" })[1])
local tinymist_id = tinymist_client.id
assert(
  tinymist_client.root_dir and vim.uv.fs_realpath(tinymist_client.root_dir) == archive,
  "Tinymist did not discover zk.toml as its workspace root"
)
vim.wait(500)
local tinymist_namespace = vim.lsp.diagnostic.get_namespace(tinymist_id)
assert(
  not vim
    .iter(vim.diagnostic.get(source_buf, { namespace = tinymist_namespace }))
    :any(function(item)
      return item.message:lower():find("unknown label", 1, true) ~= nil
    end),
  "Tinymist reported the handled Zettel reference as an unknown label"
)

zk.refresh(source_buf)
assert(
  vim.wait(5000, function()
    local marks = vim.api.nvim_buf_get_extmarks(source_buf, zk.namespace, 0, -1, { details = true })
    return vim.iter(marks):any(function(mark)
      local details = mark[4]
      return details.virt_text and details.virt_text[1] and details.virt_text[1][1] == "Target note"
    end)
  end, 20),
  "title decoration was not installed"
)
local marks = vim.api.nvim_buf_get_extmarks(source_buf, zk.namespace, 0, -1, { details = true })
assert(#marks == 1)
assert(marks[1][4].end_col > marks[1][3])
assert(marks[1][4].conceal == "")
assert(marks[1][4].virt_text_pos == "inline")

local keyword_line
for index, line in ipairs(vim.api.nvim_buf_get_lines(source_buf, 0, -1, true)) do
  if line == '#keywords("source")' then
    keyword_line = index - 1
    break
  end
end
assert(keyword_line, "keyword line not found")
vim.api.nvim_buf_set_lines(
  source_buf,
  keyword_line,
  keyword_line + 1,
  true,
  { "#keywords(computed)" }
)
local diagnostic_namespace = vim.lsp.diagnostic.get_namespace(client.id)
assert(
  vim.wait(5000, function()
    return vim
      .iter(vim.diagnostic.get(source_buf, { namespace = diagnostic_namespace }))
      :any(function(item)
        return item.code == "metadata.keywords"
      end)
  end, 20),
  "metadata diagnostic did not arrive"
)
zk.diagnostics()
assert(
  vim.iter(vim.fn.getqflist()):any(function(item)
    return item.text:find("keywords", 1, true) ~= nil
  end),
  "diagnostic quickfix entry is missing"
)
vim.cmd.cclose()
vim.api.nvim_set_current_buf(source_buf)
vim.api.nvim_buf_set_lines(
  source_buf,
  keyword_line,
  keyword_line + 1,
  true,
  { '#keywords("source")' }
)
assert(
  vim.wait(5000, function()
    return not vim
      .iter(vim.diagnostic.get(source_buf, { namespace = diagnostic_namespace }))
      :any(function(item)
        return item.code == "metadata.keywords"
      end)
  end, 20),
  "metadata diagnostic did not clear"
)

local reference_row
local reference_col
for index, line in ipairs(vim.api.nvim_buf_get_lines(source_buf, 0, -1, true)) do
  local first = line:find("@2603231411", 1, true)
  if first then
    reference_row = index
    reference_col = first
    break
  end
end
assert(reference_row, "reference not found")
vim.api.nvim_win_set_cursor(0, { reference_row, reference_col })
local definition_params = vim.lsp.util.make_position_params(0, client.offset_encoding)
local definition_response, definition_error =
  client:request_sync("textDocument/definition", definition_params, 5000, source_buf)
assert(
  definition_response and definition_response.result,
  vim.inspect(definition_error or definition_response)
)
local definition_requested = zk.definition()
assert(definition_requested, "context definition request was not sent")
local navigated = vim.wait(5000, function()
  return vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == vim.fs.normalize(target_path)
end, 20)
if not navigated then
  local windows = vim.tbl_map(function(window)
    return {
      id = window,
      buffer = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(window)),
      current = window == vim.api.nvim_get_current_win(),
    }
  end, vim.api.nvim_list_wins())
  error("context definition did not open the target: " .. vim.inspect(windows))
end
local target_buf = vim.api.nvim_get_current_buf()
assert(
  vim.wait(5000, function()
    return #vim.lsp.get_clients({ bufnr = target_buf, name = "zk" }) == 1
  end, 20),
  "zk lsp did not attach to target"
)

zk.backlinks()
assert(
  vim.wait(5000, function()
    return #vim.fn.getqflist() == 1
  end, 20),
  "backlink quickfix entry did not arrive"
)
local backlink = vim.fn.getqflist()[1]
assert(vim.fs.normalize(vim.api.nvim_buf_get_name(backlink.bufnr)) == vim.fs.normalize(source_path))
vim.cmd.cclose()
vim.api.nvim_set_current_buf(target_buf)

local selected
vim.ui.select = function(items, _, callback)
  selected = items[1]
  callback(items[1])
end
zk.find("Source note")
assert(
  vim.wait(5000, function()
    return selected ~= nil
      and vim.fs.normalize(vim.api.nvim_buf_get_name(0)) == vim.fs.normalize(source_path)
  end, 20),
  "archive search did not open the selected Zettel"
)

local blocked
zk.remove("2603231411", function(result)
  blocked = result
end)
assert(
  vim.wait(5000, function()
    return blocked ~= nil
  end, 20),
  "blocked removal did not finish"
)
assert(blocked.code ~= 0)
assert(vim.uv.fs_stat(target_path), "blocked removal deleted the target")

vim.cmd.edit(vim.fn.fnameescape(removable_path))
local removable_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(removable_buf, -1, -1, true, { "Unsaved local change." })
assert(vim.bo[removable_buf].modified)
assert(zk.remove("2603231412") == nil, "modified Zettel removal was not rejected")
assert(vim.uv.fs_stat(removable_path), "modified Zettel was removed")
vim.bo[removable_buf].modified = false
vim.api.nvim_set_current_buf(source_buf)

local removed
zk.remove("2603231412", function(result)
  removed = result
end)
assert(
  vim.wait(5000, function()
    return removed ~= nil
  end, 20),
  "successful removal did not finish"
)
assert(removed.code == 0)
assert(not vim.uv.fs_stat(removable_path), "removable Zettel still exists")

local created
zk.new(function(result)
  created = result
end)
assert(
  vim.wait(5000, function()
    return created ~= nil
  end, 20),
  "Zettel creation did not finish"
)
assert(created.code == 0)
local created_path = vim.api.nvim_buf_get_name(0)
assert(created_path:match("/zettel/%d%d%d%d%d%d%d%d%d%d%.typ$"))
assert(vim.uv.fs_stat(created_path), "created Zettel is missing")

vim.cmd.edit(vim.fn.fnameescape(source_path))
local checked
zk.check(function(result)
  checked = result
end)
assert(
  vim.wait(5000, function()
    return checked ~= nil
  end, 20),
  "archive check did not finish"
)
assert(checked.code == 0)

local report = {
  client = client.name,
  commands = true,
  mappings = true,
  decorations = true,
  diagnostics = true,
  contextDefinition = true,
  backlinks = true,
  search = true,
  blockedRemoval = true,
  successfulRemoval = true,
  unsavedRemovalGuard = true,
  newZettel = true,
  check = true,
  tinymistAttached = true,
  tinymistRoot = true,
}
vim.fn.writefile({ vim.json.encode(report) }, report_path)

for _, lsp_client in ipairs(vim.lsp.get_clients()) do
  if lsp_client.name == "zk" or lsp_client.name == "tinymist" then
    lsp_client:stop(true)
  end
end
vim.cmd.qa({ bang = true })
