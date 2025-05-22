local M = {}

local aderyn = require('aderyn-diagnostics.aderyn')
local config = require('aderyn-diagnostics.config')

---Setup the Aderyn diagnostics plugin
---@param opts table|nil Configuration options
function M.setup(opts)
	config.setup(opts)

	-- Set up autocommands to attach to appropriate filetypes
	local group = vim.api.nvim_create_augroup("AderynDiagnostics", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = config.filetypes,
		callback = function(args)
			config.on_attach(args.buf)
		end,
	})

	-- Set up autocommand to run Aderyn when Solidity files are saved
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = "*.sol",
		callback = function()
			if config.enabled then
				-- Add a small delay to ensure file is written
				vim.defer_fn(function()
					aderyn.aderyn()
				end, 100)
			end
		end,
	})

	-- Run Aderyn initially if enabled
	if config.enabled then
		-- Add a slight delay to ensure everything is set up
		vim.defer_fn(function()
			aderyn.aderyn()
		end, 500)
	end
end

-- Re-export the config for other modules to use
M.config = config

return M
