local suite = assert(arg[1], "choose unit, integration, or tinymist")
assert(
  vim.tbl_contains({ "unit", "integration", "tinymist" }, suite),
  "unknown test suite: " .. suite
)
assert(vim.fn.has("nvim-0.12") == 1, "tests require Neovim 0.12 or newer")
local dependency = vim.fs.joinpath(vim.uv.cwd(), ".deps/mini.test")
assert(vim.uv.fs_stat(vim.fs.joinpath(dependency, "lua/mini/test.lua")), "run just deps first")
if suite ~= "unit" then
  local binary = vim.env.ZK_BIN
  assert(binary and binary ~= "", "set ZK_BIN to the engine build to test")
  binary = vim.fn.exepath(binary)
  assert(binary ~= "", "ZK_BIN is not executable")
  vim.env.ZK_BIN = binary
end
if suite == "tinymist" then
  local binary = vim.fn.exepath(vim.env.TINYMIST_BIN or "tinymist")
  assert(binary ~= "", "Tinymist is required; optionally set TINYMIST_BIN")
  vim.env.TINYMIST_BIN = binary
end
vim.opt.runtimepath:prepend(dependency)
vim.opt.runtimepath:prepend(vim.uv.cwd())
local MiniTest = require("mini.test")
MiniTest.setup({
  collect = {
    find_files = function()
      return vim.fn.glob("tests/" .. suite .. "/test_*.lua", false, true)
    end,
    filter_cases = function(case)
      local filter = vim.env.TEST_FILTER
      return not filter or table.concat(case.desc, " "):find(filter, 1, true) ~= nil
    end,
  },
  execute = { reporter = MiniTest.gen_reporter.stdout() },
})
local cases = MiniTest.collect()
assert(#cases > 0, "no tests collected for " .. suite)
MiniTest.execute(cases)
