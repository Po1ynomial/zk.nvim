local M = {}

M.version = 2
M.data_schema_version = 2

function M.validate(initialize_result)
  local descriptor = vim.tbl_get(initialize_result, "capabilities", "experimental", "zk")
  if type(descriptor) ~= "table" or type(descriptor.protocolVersion) ~= "number" then
    return nil, "zk language server did not report a ZK protocol version"
  end
  if descriptor.protocolVersion ~= M.version then
    return nil,
      string.format(
        "unsupported ZK protocol version %s; zk.nvim supports version %d",
        descriptor.protocolVersion,
        M.version
      )
  end
  if type(descriptor.dataSchemaVersion) ~= "number" then
    return nil, "zk language server did not report a data schema version"
  end
  if descriptor.dataSchemaVersion ~= M.data_schema_version then
    return nil,
      string.format(
        "unsupported ZK data schema version %s; zk.nvim supports version %d",
        descriptor.dataSchemaVersion,
        M.data_schema_version
      )
  end
  return {
    version = descriptor.protocolVersion,
    data_schema_version = descriptor.dataSchemaVersion,
    features = type(descriptor.features) == "table" and descriptor.features or {},
  },
    nil
end

function M.unwrap(envelope)
  if type(envelope) ~= "table" or type(envelope.schema_version) ~= "number" then
    return nil, "zk result did not report a data schema version"
  end
  if envelope.schema_version ~= M.data_schema_version then
    return nil, "unsupported ZK result data schema version " .. tostring(envelope.schema_version)
  end
  if type(envelope.data) ~= "table" or envelope.data == vim.NIL then
    return nil, "zk result did not contain archive data"
  end
  return envelope.data, nil
end

function M.has(client, feature)
  return not not (
    client.config
    and client.config.zk_protocol
    and client.config.zk_protocol.features[feature] == true
  )
end

return M
