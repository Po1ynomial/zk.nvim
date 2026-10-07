local MiniTest = require("mini.test")
local protocol = require("zk.protocol")
local T = MiniTest.new_set()
local function initialize(descriptor)
  return { capabilities = { experimental = { zk = descriptor } } }
end

T["accepts both versions and ignores unknown capabilities"] = function()
  local descriptor, err = protocol.validate(initialize({
    protocolVersion = 2,
    dataSchemaVersion = 2,
    features = { archiveQueries = true, futureFeature = true },
    futureProperty = {},
  }))
  assert(not err, err)
  MiniTest.expect.equality(descriptor.version, 2)
  MiniTest.expect.equality(descriptor.data_schema_version, 2)
  assert(protocol.has({ config = { zk_protocol = descriptor } }, "archiveQueries"))
end

T["missing optional features default to false"] = function()
  local descriptor =
    assert(protocol.validate(initialize({ protocolVersion = 2, dataSchemaVersion = 2 })))
  MiniTest.expect.equality(
    protocol.has({ config = { zk_protocol = descriptor } }, "archiveQueries"),
    false
  )
  MiniTest.expect.equality(protocol.has({}, "referenceTitleDecorations"), false)
end

T["rejects missing, old, future, and nonnumeric versions"] = function()
  for _, descriptor in ipairs({
    {},
    { protocolVersion = 1, dataSchemaVersion = 2 },
    { protocolVersion = 3, dataSchemaVersion = 2 },
    { protocolVersion = 2 },
    { protocolVersion = 2, dataSchemaVersion = 1 },
    { protocolVersion = 2, dataSchemaVersion = 3 },
    { protocolVersion = "2", dataSchemaVersion = 2 },
    { protocolVersion = 2, dataSchemaVersion = "2" },
  }) do
    local result, err = protocol.validate(initialize(descriptor))
    assert(not result and err, vim.inspect(descriptor))
  end
end

T["envelopes preserve null, empty, and unfamiliar metadata"] = function()
  local node = {
    id = "2603231410",
    path = "zettel/2603231410.typ",
    title = vim.NIL,
    metadata = {
      absent = vim.NIL,
      tags = { kind = "string-list", value = {} },
      summary = {
        kind = "markup",
        value = { source = "", text = "", range = { start = 0, ["end"] = 0 } },
      },
      unfamiliar = { kind = "future-kind", value = { nested = true } },
    },
  }
  MiniTest.expect.equality(
    protocol.unwrap({ schema_version = 2, data = node, futureProperty = true }) == node,
    true
  )
  local empty = {}
  MiniTest.expect.equality(protocol.unwrap({ schema_version = 2, data = empty }) == empty, true)
end

T["rejects unsupported or malformed envelopes"] = function()
  for _, envelope in ipairs({
    {},
    { id = "2603231410" },
    { schema_version = 1, data = {} },
    { schema_version = 3, data = {} },
    { schema_version = "2", data = {} },
    { schema_version = 2, data = vim.NIL },
    { schema_version = 2 },
  }) do
    local result, err = protocol.unwrap(envelope)
    assert(not result and err, vim.inspect(envelope))
  end
end

T["deprecated completion helper never intercepts Tinymist"] = function()
  local items = { { client_name = "zk" }, { client_name = "tinymist" } }
  MiniTest.expect.equality(
    require("zk").filter_completion_items({ line = "#category.th", cursor = { 1, 12 } }, items)
      == items,
    true
  )
  MiniTest.expect.equality(
    require("zk").filter_completion_items({ line = "#text.", cursor = { 1, 6 } }, items) == items,
    true
  )
end

return T
