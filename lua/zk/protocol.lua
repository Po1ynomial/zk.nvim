local M = {}

M.version = 1

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
  if type(descriptor.features) ~= "table" then
    return nil, "zk language server did not report ZK protocol features"
  end
  return {
    version = descriptor.protocolVersion,
    features = descriptor.features,
  }, nil
end

function M.has(client, feature)
  return client.config
    and client.config.zk_protocol
    and client.config.zk_protocol.features[feature] == true
end

return M
