vim.opt.runtimepath:prepend(vim.uv.cwd())
vim.opt.runtimepath:append(vim.fs.joinpath(vim.uv.cwd(), "after"))
vim.o.swapfile = false
vim.cmd("filetype plugin on")
