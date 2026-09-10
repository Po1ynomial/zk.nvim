local M = {}

local namespace = vim.api.nvim_create_namespace("zk.references")
local group
local refresh_tokens = {}
local configured = false
local fallback_client_id
local pending_clients = {}
local switch_token = 0
local schedule_refresh
local set_mappings

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
M.archive = nil

local function completion_line_before_cursor(context)
  local line = context and context.line or nil
  local cursor = context and context.cursor or nil
  local bufnr = context and context.bufnr or vim.api.nvim_get_current_buf()
  if not cursor then
    cursor = vim.api.nvim_win_get_cursor(0)
  end
  if not line then
    line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], true)[1] or ""
  end
  return line:sub(1, cursor[2])
end

local function completion_client_name(item)
  if item.client_name then
    return item.client_name
  end
  local client_id = item.client_id or vim.tbl_get(item, "user_data", "nvim", "lsp", "client_id")
  local client = client_id and vim.lsp.get_client_by_id(client_id) or nil
  return client and client.name or nil
end

function M.filter_completion_items(context, items)
  local before = completion_line_before_cursor(context)
  if not before:match("^#category%.[%w_-]*$") then
    return items
  end
  return vim.tbl_filter(function(item)
    return completion_client_name(item) == "zk"
  end, items)
end

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
  local root = vim.fs.root(path, "zk.toml")
  return root and (vim.uv.fs_realpath(root) or vim.fs.normalize(root)) or nil
end

local function zk_client(bufnr)
  return vim.iter(vim.lsp.get_clients({ bufnr = bufnr, name = "zk" })):next()
end

local function same_root(left, right)
  if not left or not right then
    return false
  end
  left = vim.uv.fs_realpath(left) or vim.fs.normalize(left)
  right = vim.uv.fs_realpath(right) or vim.fs.normalize(right)
  return left == right
end

local function zk_client_for_root(root)
  return vim.iter(vim.lsp.get_clients({ name = "zk" })):find(function(client)
    return same_root(client.root_dir, root)
  end)
end

local function selected_root(bufnr)
  return archive_root(bufnr) or M.archive
end

local function finish_client_start(root, client, error_message)
  local waiters = pending_clients[root] or {}
  pending_clients[root] = nil
  for _, callback in ipairs(waiters) do
    callback(client, error_message)
  end
end

local function ensure_client(root, callback)
  local client = zk_client_for_root(root)
  if client and client.initialized then
    callback(client, nil)
    return client.id
  end

  pending_clients[root] = pending_clients[root] or {}
  table.insert(pending_clients[root], callback)
  if client then
    return client.id
  end

  local client_id = vim.lsp.start({
    name = "zk",
    cmd = config.lsp_cmd,
    cmd_cwd = root,
    root_dir = root,
    on_attach = function(attached_client, attached_bufnr)
      if attached_client.name ~= "zk" then
        return
      end
      set_mappings(attached_bufnr)
      schedule_refresh(attached_bufnr)
    end,
    on_init = function(started_client)
      finish_client_start(root, started_client, nil)
    end,
    on_exit = function(code, _, stopped_client_id)
      if fallback_client_id == stopped_client_id then
        fallback_client_id = nil
      end
      if pending_clients[root] then
        vim.schedule(function()
          finish_client_start(
            root,
            nil,
            "zk language server exited before initialization with code " .. code
          )
        end)
      end
    end,
  }, { attach = false })

  if not client_id then
    finish_client_start(root, nil, "could not start zk language server")
    return nil
  end
  return client_id
end

local function with_selected_client(bufnr, callback)
  local root = selected_root(bufnr)
  if not root then
    notify("no Zettelkasten archive found", vim.log.levels.ERROR)
    return nil
  end
  return ensure_client(root, function(client, error_message)
    if not client then
      notify(error_message, vim.log.levels.ERROR)
      return
    end
    callback(client, root)
  end)
end

local function resolve_archive(value)
  if type(value) ~= "string" or value == "" then
    return nil, "archive path must be a non-empty string"
  end
  local expanded = vim.fn.expand(value)
  local absolute = vim.fn.fnamemodify(expanded, ":p")
  local root = vim.uv.fs_realpath(absolute)
  if not root then
    return nil, "archive path does not exist: " .. absolute
  end
  local required = {
    { path = "zk.toml", kind = "file" },
    { path = "zettel", kind = "directory" },
    { path = "lib/zettel.typ", kind = "file" },
  }
  for _, item in ipairs(required) do
    local path = vim.fs.joinpath(root, item.path)
    local stat = vim.uv.fs_stat(path)
    if not stat or stat.type ~= item.kind then
      return nil, "archive is missing required " .. item.path .. ": " .. root
    end
  end
  return root, nil
end

local function stop_fallback_client(client_id)
  local client = client_id and vim.lsp.get_client_by_id(client_id) or nil
  if client and vim.tbl_isempty(client.attached_buffers) then
    client:stop()
  end
end

local function select_fallback(value, announce)
  local root, error_message = resolve_archive(value)
  if not root then
    notify(error_message, vim.log.levels.ERROR)
    return nil
  end

  switch_token = switch_token + 1
  local token = switch_token
  local previous_client_id = fallback_client_id
  ensure_client(root, function(client, start_error)
    if token ~= switch_token then
      if client and not same_root(client.root_dir, M.archive) then
        stop_fallback_client(client.id)
      end
      return
    end
    if not client then
      notify(start_error, vim.log.levels.ERROR)
      return
    end
    M.archive = root
    fallback_client_id = client.id
    if previous_client_id ~= client.id then
      stop_fallback_client(previous_client_id)
    end
    if announce then
      notify("using Zettelkasten archive " .. root)
    end
  end)
  return root
end

function M.set_archive(value)
  if not value or value == "" then
    notify(M.archive or "no fallback Zettelkasten archive configured")
    return M.archive
  end
  return select_fallback(value, true)
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

schedule_refresh = function(bufnr)
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

local function edit_path(path)
  vim.cmd("hide edit " .. vim.fn.fnameescape(path))
end

local function show_document(location, client, source_bufnr)
  if vim.api.nvim_get_current_buf() == source_bufnr and vim.bo[source_bufnr].modified then
    vim.cmd.split()
  end
  local word_ok, word = pcall(vim.fn.expand, "<cword>")
  if not word_ok or word == "" then
    local shown = vim.lsp.util.show_document(location, client.offset_encoding, {
      focus = false,
      reuse_win = true,
    })
    if shown then
      local uri = location.uri or location.targetUri
      local target_bufnr = uri and vim.uri_to_bufnr(uri) or nil
      local target_window = target_bufnr and vim.fn.win_findbuf(target_bufnr)[1] or nil
      if target_window then
        vim.api.nvim_set_current_win(target_window)
      end
    end
    return shown
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
  return with_selected_client(bufnr, function(client)
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
  end)
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
  local bufnr = vim.api.nvim_get_current_buf()
  return with_selected_client(bufnr, function(client)
    vim.diagnostic.setqflist({
      namespace = vim.lsp.diagnostic.get_namespace(client.id),
      open = true,
      title = "Zettelkasten diagnostics",
    })
  end)
end

local function run_cli(bufnr, arguments, callback)
  local root = selected_root(bufnr)
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
      edit_path(path)
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
  local root = selected_root(bufnr)
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

set_mappings = function(bufnr)
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
  ensure_client(root, function(client, error_message)
    if not client then
      notify(error_message, vim.log.levels.ERROR)
      return
    end
    vim.lsp.buf_attach_client(bufnr, client.id)
  end)
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
  vim.api.nvim_create_user_command("ZkSetArchive", function(command)
    M.set_archive(command.args)
  end, { nargs = "?", complete = "dir", force = true })
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
  if config.archive then
    select_fallback(config.archive, false)
  elseif M.archive then
    switch_token = switch_token + 1
    local previous_client_id = fallback_client_id
    M.archive = nil
    fallback_client_id = nil
    stop_fallback_client(previous_client_id)
  end
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
