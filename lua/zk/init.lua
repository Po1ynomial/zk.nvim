local M = {}

local namespace = vim.api.nvim_create_namespace("zk.references")
local group
local refresh_tokens = {}
local configured = false

local defaults = {
  lsp_cmd = { "zk", "lsp" },
  cli_cmd = { "zk" },
  decorations = true,
  debounce_ms = 120,
  mappings = {
    definition = "gd",
    find = "<leader>zf",
    backlinks = "<leader>zb",
    diagnostics = "<leader>zd",
    new = "<leader>zn",
  },
}

local config = vim.deepcopy(defaults)

M.namespace = namespace

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "zk" })
end

local function zettel_id(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  local name = vim.fs.basename(path)
  local id = name:match("^(%d%d%d%d%d%d%d%d%d%d)%.typ$")
  if not id or vim.fs.basename(vim.fs.dirname(path)) ~= "zettel" then
    return nil
  end
  return id
end

local function archive_root(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" then
    path = vim.uv.cwd()
  end
  return vim.fs.root(path, "zk.toml")
end

local function zk_client(bufnr)
  return vim.iter(vim.lsp.get_clients({ bufnr = bufnr, name = "zk" })):next()
end

local function execute(client, bufnr, command, arguments, callback, quiet)
  client:request("workspace/executeCommand", {
    command = command,
    arguments = arguments,
  }, function(error, result)
    vim.schedule(function()
      if error then
        if not quiet then
          notify(error.message or tostring(error), vim.log.levels.ERROR)
        end
        callback(nil, error)
        return
      end
      callback(result, nil)
    end)
  end, bufnr)
end

local function buffer_text(bufnr)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, true), "\n")
end

local function byte_position(text, offset)
  if offset < 0 or offset > #text then
    return nil
  end
  local row = 0
  local line_start = 1
  while true do
    local newline = text:find("\n", line_start, true)
    local line_end = newline and (newline - 1) or #text
    local line_length = line_end - line_start + 1
    if offset <= (line_start - 1) + line_length then
      return row, offset - (line_start - 1)
    end
    if not newline then
      return nil
    end
    row = row + 1
    line_start = newline + 1
  end
end

local function set_conceallevel(bufnr)
  for _, window in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(window) == bufnr then
      vim.wo[window].conceallevel = math.max(vim.wo[window].conceallevel, 2)
    end
  end
end

local function apply_decorations(bufnr, token, changedtick, links, titles)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if refresh_tokens[bufnr] ~= token or vim.api.nvim_buf_get_changedtick(bufnr) ~= changedtick then
    return
  end

  local text = buffer_text(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  set_conceallevel(bufnr)
  for _, link in ipairs(links) do
    local title = titles[link.target]
    local highlight = "ZkReference"
    if link.resolution == "missing" then
      title = "Missing " .. link.target
      highlight = "ZkMissingReference"
    elseif not title or title == "" then
      title = link.target
    end
    for _, span in ipairs(link.spans or {}) do
      local row, col = byte_position(text, span.start)
      local end_row, end_col = byte_position(text, span["end"])
      if row and end_row then
        vim.api.nvim_buf_set_extmark(bufnr, namespace, row, col, {
          end_row = end_row,
          end_col = end_col,
          conceal = "",
          virt_text = { { title, highlight } },
          virt_text_pos = "inline",
          hl_mode = "combine",
          priority = 120,
          invalidate = true,
        })
      end
    end
  end
end

function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not config.decorations or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local id = zettel_id(bufnr)
  local client = zk_client(bufnr)
  if not id or not client then
    vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
    return
  end

  local token = (refresh_tokens[bufnr] or 0) + 1
  refresh_tokens[bufnr] = token
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  execute(client, bufnr, "zk.links", { id }, function(links)
    if not links then
      return
    end
    local targets = {}
    for _, link in ipairs(links) do
      if link.resolution == "resolved" then
        targets[link.target] = true
      end
    end
    local pending = vim.tbl_count(targets)
    local titles = {}
    if pending == 0 then
      apply_decorations(bufnr, token, changedtick, links, titles)
      return
    end
    for target in pairs(targets) do
      execute(client, bufnr, "zk.queryNode", { target }, function(node)
        if node and node.title then
          titles[target] = node.title.text
        end
        pending = pending - 1
        if pending == 0 then
          apply_decorations(bufnr, token, changedtick, links, titles)
        end
      end, true)
    end
  end)
end

local function schedule_refresh(bufnr)
  local token = (refresh_tokens[bufnr] or 0) + 1
  refresh_tokens[bufnr] = token
  vim.defer_fn(function()
    if refresh_tokens[bufnr] == token then
      M.refresh(bufnr)
    end
  end, config.debounce_ms)
end

local function cursor_on_reference()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local column = cursor[2] + 1
  local start = 1
  while true do
    local first, last = line:find("@%d%d%d%d%d%d%d%d%d%d", start)
    if not first then
      return false
    end
    if first <= column and column <= last then
      return true
    end
    start = last + 1
  end
end

local function edit_path(path, source_bufnr)
  if vim.api.nvim_get_current_buf() == source_bufnr and vim.bo[source_bufnr].modified then
    vim.cmd.split()
  end
  vim.cmd.edit(vim.fn.fnameescape(path))
end

local function show_document(location, client, source_bufnr)
  if vim.api.nvim_get_current_buf() == source_bufnr and vim.bo[source_bufnr].modified then
    vim.cmd.split()
  end
  return vim.lsp.util.show_document(location, client.offset_encoding, {
    focus = true,
    reuse_win = true,
  })
end

function M.definition()
  local bufnr = vim.api.nvim_get_current_buf()
  local client = zk_client(bufnr)
  if not client or not cursor_on_reference() then
    vim.lsp.buf.definition()
    return
  end
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  return client:request("textDocument/definition", params, function(error, result)
    vim.schedule(function()
      if error then
        notify(error.message or tostring(error), vim.log.levels.ERROR)
        return
      end
      local location = result
      if vim.islist(result) then
        location = result[1]
      end
      if location and not show_document(location, client, bufnr) then
        notify("could not open Zettel definition", vim.log.levels.ERROR)
      end
    end)
  end, bufnr)
end

function M.find(query)
  local bufnr = vim.api.nvim_get_current_buf()
  local client = zk_client(bufnr)
  if not client then
    notify("zk language server is not attached", vim.log.levels.ERROR)
    return
  end
  client:request("workspace/symbol", { query = query or "" }, function(error, symbols)
    vim.schedule(function()
      if error then
        notify(error.message or tostring(error), vim.log.levels.ERROR)
        return
      end
      if not symbols or vim.tbl_isempty(symbols) then
        notify("no matching Zettel")
        return
      end
      vim.ui.select(symbols, {
        prompt = "Zettel",
        format_item = function(symbol)
          return symbol.name
        end,
      }, function(symbol)
        if symbol then
          show_document(symbol.location, client, bufnr)
        end
      end)
    end)
  end, bufnr)
end

local function text_for_source(root, id)
  local path = vim.fs.joinpath(root, "zettel", id .. ".typ")
  local normalized = vim.fs.normalize(path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_loaded(bufnr)
      and vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr)) == normalized
    then
      return path, buffer_text(bufnr)
    end
  end
  local file = io.open(path, "rb")
  if not file then
    return path, nil
  end
  local text = file:read("*a")
  file:close()
  return path, text
end

function M.backlinks()
  local bufnr = vim.api.nvim_get_current_buf()
  local id = zettel_id(bufnr)
  local root = archive_root(bufnr)
  local client = zk_client(bufnr)
  if not id or not root or not client then
    notify("current buffer is not an attached Zettel", vim.log.levels.ERROR)
    return
  end
  execute(client, bufnr, "zk.backlinks", { id }, function(links)
    if not links then
      return
    end
    local items = {}
    for _, link in ipairs(links) do
      local path, text = text_for_source(root, link.source)
      if text then
        local lines = vim.split(text, "\n", { plain = true })
        for _, span in ipairs(link.spans or {}) do
          local row, col = byte_position(text, span.start)
          if row then
            table.insert(items, {
              filename = path,
              lnum = row + 1,
              col = col + 1,
              text = lines[row + 1] or "",
            })
          end
        end
      end
    end
    vim.fn.setqflist({}, " ", { title = "Zettel backlinks for " .. id, items = items })
    if #items > 0 then
      vim.cmd.copen()
    else
      notify("no backlinks")
    end
  end)
end

function M.diagnostics()
  local client = zk_client(vim.api.nvim_get_current_buf())
  if not client then
    notify("zk language server is not attached", vim.log.levels.ERROR)
    return
  end
  vim.diagnostic.setqflist({
    namespace = vim.lsp.diagnostic.get_namespace(client.id),
    open = true,
    title = "Zettelkasten diagnostics",
  })
end

local function run_cli(bufnr, arguments, callback)
  local root = archive_root(bufnr)
  if not root then
    notify("no Zettelkasten archive found", vim.log.levels.ERROR)
    return nil
  end
  local command = vim.list_extend(vim.deepcopy(config.cli_cmd), arguments)
  return vim.system(command, { cwd = root, text = true }, function(result)
    vim.schedule(function()
      if callback then
        callback(result, root)
      elseif result.code ~= 0 then
        notify(vim.trim(result.stderr), vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.check(callback)
  return run_cli(vim.api.nvim_get_current_buf(), { "check" }, function(result)
    local output = vim.trim((result.stdout or "") .. (result.stderr or ""))
    notify(output, result.code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
    if callback then
      callback(result)
    end
  end)
end

function M.new(callback)
  local bufnr = vim.api.nvim_get_current_buf()
  return run_cli(bufnr, { "new" }, function(result, root)
    if result.code ~= 0 then
      notify(vim.trim(result.stderr), vim.log.levels.ERROR)
    else
      local path = vim.fs.joinpath(root, vim.trim(result.stdout))
      edit_path(path, bufnr)
    end
    if callback then
      callback(result)
    end
  end)
end

function M.remove(id, callback)
  local bufnr = vim.api.nvim_get_current_buf()
  id = id and id ~= "" and id or zettel_id(bufnr)
  if not id then
    notify("no Zettel ID supplied", vim.log.levels.ERROR)
    return nil
  end
  local root = archive_root(bufnr)
  if not root then
    notify("no Zettelkasten archive found", vim.log.levels.ERROR)
    return nil
  end
  local target = vim.fs.normalize(vim.fs.joinpath(root, "zettel", id .. ".typ"))
  for _, loaded in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_loaded(loaded)
      and vim.fs.normalize(vim.api.nvim_buf_get_name(loaded)) == target
      and vim.bo[loaded].modified
    then
      notify("cannot remove a Zettel with unsaved changes", vim.log.levels.ERROR)
      return nil
    end
  end
  return run_cli(bufnr, { "remove", id }, function(result, root)
    if result.code ~= 0 then
      notify(vim.trim(result.stderr), vim.log.levels.ERROR)
    else
      local removed = vim.fs.normalize(vim.fs.joinpath(root, vim.trim(result.stdout)))
      for _, loaded in ipairs(vim.api.nvim_list_bufs()) do
        if
          vim.api.nvim_buf_is_valid(loaded)
          and vim.fs.normalize(vim.api.nvim_buf_get_name(loaded)) == removed
        then
          vim.api.nvim_buf_delete(loaded, { force = true })
        end
      end
      notify("removed " .. id)
    end
    if callback then
      callback(result)
    end
  end)
end

local function set_mappings(bufnr)
  if config.mappings == false then
    return
  end
  local mappings = config.mappings
  local options = { buffer = bufnr, silent = true }
  if mappings.definition then
    vim.keymap.set("n", mappings.definition, M.definition, options)
  end
  if mappings.find then
    vim.keymap.set("n", mappings.find, function()
      M.find("")
    end, options)
  end
  if mappings.backlinks then
    vim.keymap.set("n", mappings.backlinks, M.backlinks, options)
  end
  if mappings.diagnostics then
    vim.keymap.set("n", mappings.diagnostics, M.diagnostics, options)
  end
  if mappings.new then
    vim.keymap.set("n", mappings.new, M.new, options)
  end
end

local function attach(bufnr)
  local id = zettel_id(bufnr)
  local root = archive_root(bufnr)
  if not id or not root then
    return
  end
  vim.lsp.start({
    name = "zk",
    cmd = config.lsp_cmd,
    cmd_cwd = root,
    root_dir = root,
    on_attach = function(client, attached_bufnr)
      if client.name ~= "zk" then
        return
      end
      set_mappings(attached_bufnr)
      schedule_refresh(attached_bufnr)
    end,
  }, { bufnr = bufnr })
end

local function create_commands()
  vim.api.nvim_create_user_command("ZkFind", function(command)
    M.find(command.args)
  end, { nargs = "?", force = true })
  vim.api.nvim_create_user_command("ZkBacklinks", M.backlinks, { force = true })
  vim.api.nvim_create_user_command("ZkDiagnostics", M.diagnostics, { force = true })
  vim.api.nvim_create_user_command("ZkCheck", function()
    M.check()
  end, { force = true })
  vim.api.nvim_create_user_command("ZkNew", function()
    M.new()
  end, { force = true })
  vim.api.nvim_create_user_command("ZkRemove", function(command)
    M.remove(command.args)
  end, { nargs = "?", force = true })
  vim.api.nvim_create_user_command("ZkRefresh", function()
    M.refresh()
  end, { force = true })
end

function M.setup(options)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), options or {})
  vim.api.nvim_set_hl(0, "ZkReference", { default = true, link = "Underlined" })
  vim.api.nvim_set_hl(0, "ZkMissingReference", { default = true, link = "DiagnosticError" })
  create_commands()
  group = vim.api.nvim_create_augroup("zk.nvim", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "typst",
    callback = function(event)
      attach(event.buf)
    end,
  })
  vim.api.nvim_create_autocmd(
    { "TextChanged", "TextChangedI", "DiagnosticChanged", "BufWinEnter" },
    {
      group = group,
      callback = function(event)
        if zettel_id(event.buf) then
          schedule_refresh(event.buf)
        end
      end,
    }
  )
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    callback = function(event)
      refresh_tokens[event.buf] = nil
    end,
  })
  configured = true
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == "typst" then
      attach(bufnr)
    end
  end
end

function M.is_configured()
  return configured
end

return M
