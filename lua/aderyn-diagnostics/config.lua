local M = {}
local namespace = vim.api.nvim_create_namespace("aderyn-nvim")

M.enabled = true
-- Corresponds to the root directory where Aderyn should run (usually project root with contracts)
M.aderyn_root = ""
-- Map Aderyn issue severity to vim diagnostic severity
M.severity_map = {
	high = vim.diagnostic.severity.ERROR,
	-- Most aderyn findings at Low level are closer to informationals
	low = vim.diagnostic.severity.HINT,
}
-- Used when the severity can't be parsed from the aderyn result.
---@type integer
M.default_severity = vim.diagnostic.severity.INFO
-- Show all results by default.
---@type integer
M.minimum_severity = vim.diagnostic.severity.HINT
M.extra_args = {}
-- Aderyn works with Solidity files
M.filetypes = { "solidity" }

---Print current configuration to the user
function M.print_config()
	local config_lines = { "Current Aderyn Configuration:" }
	for k, v in pairs(M) do
		if type(v) == "table" and type(k) == "string" then
			table.insert(config_lines, string.format("%s: %s", k, vim.inspect(v)))
		elseif type(k) == "string" then
			table.insert(config_lines, string.format("%s: %s", k, tostring(v)))
		end
	end
	vim.notify(table.concat(config_lines, "\n"), vim.log.levels.INFO)
end

---Toggle Aderyn diagnostics on/off
function M.toggle()
	-- Toggle the enabled state
	M.enabled = not M.enabled
	if not M.enabled then
		-- Clear all diagnostics when disabling
		local bufs = vim.api.nvim_list_bufs()
		for _, buf in ipairs(bufs) do
			if vim.api.nvim_buf_is_valid(buf) then
				vim.diagnostic.reset(namespace, buf)
			end
		end
		vim.notify("Aderyn diagnostics disabled", vim.log.levels.INFO)
	else
		vim.notify("Aderyn diagnostics enabled", vim.log.levels.INFO)
		require('aderyn-diagnostics.aderyn').aderyn()
	end
end

---Set up key mappings for the plugin
---@param bufnr integer Buffer number to attach to
function M.on_attach(bufnr)
	local opts = { buffer = bufnr }

	vim.keymap.set("n", "<leader>at", function() M.toggle() end,
		vim.tbl_extend("force", opts, { desc = "[A]deryn [T]oggle diagnostics" }))

	vim.keymap.set("n", "<leader>ac", function() M.print_config() end,
		vim.tbl_extend("force", opts, { desc = "[A]deryn print [C]onfig" }))

	local aderyn = require('aderyn-diagnostics.aderyn')
	vim.keymap.set('n', '<leader>ad', function() aderyn.show_issue_details() end,
		vim.tbl_extend("force", opts, { desc = '[A]deryn show issue [D]etails' }))

	vim.keymap.set('n', '<leader>ar', function() aderyn.aderyn() end,
		vim.tbl_extend("force", opts, { desc = '[A]deryn [R]un analysis' }))

	vim.keymap.set('n', '<leader>av', function()
		vim.ui.select(
			{ "ERROR", "WARN", "INFO", "HINT" },
			{
				prompt = "Select minimum severity level:",
				format_item = function(item)
					return string.format("%s (%d)", item, vim.diagnostic.severity[item])
				end,
			},
			function(choice)
				if choice then
					local severity = vim.diagnostic.severity[choice]
					M.set_minimum_severity(severity)
				end
			end
		)
	end, vim.tbl_extend("force", opts, { desc = "[A]deryn set minimum se[v]erity" }))
end

---Set the minimum severity level for displaying diagnostics
---@param level integer Severity level from vim.diagnostic.severity
function M.set_minimum_severity(level)
	if not vim.tbl_contains(vim.tbl_values(vim.diagnostic.severity), level) then
		vim.notify("Invalid severity level", vim.log.levels.ERROR)
		return
	end
	M.minimum_severity = level
	vim.notify(string.format("Minimum severity set to: %s", level), vim.log.levels.INFO)
end

---Setup function to configure the plugin
---@param opts table|nil Configuration options
function M.setup(opts)
    if opts then
        local updated = vim.tbl_deep_extend("force", M, opts)
        for k, v in pairs(updated) do
            M[k] = v
        end
    end
end

return M
