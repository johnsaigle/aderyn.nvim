local M = {}

local config = require('aderyn-diagnostics.config')

---Check if an Aderyn issue instance is valid for creating diagnostics
---@param instance table Issue instance from Aderyn output
---@return boolean
local function is_valid_instance(instance)
	return instance.contract_path and
	    instance.line_no and
	    type(instance.line_no) == "number"
end

---Convert Aderyn issue severity to vim diagnostic severity
---@param issue_type string Either "high" or "low"
---@return integer Vim diagnostic severity level
local function get_severity(issue_type)
	return config.severity_map[issue_type] or config.default_severity
end

---Run Aderyn analysis and populate diagnostics with the results
function M.aderyn()
	local null_ls_ok, null_ls = pcall(require, "null-ls")
	if not null_ls_ok then
		vim.notify("none-ls is required for aderyn-nvim", vim.log.levels.ERROR)
		return
	end

	local aderyn_generator = {
		method = null_ls.methods.DIAGNOSTICS,
		filetypes = config.filetypes,
		generator = {
			-- Configure when to run the diagnostics
			runtime_condition = function()
				return config.enabled
			end,
			fn = function(params)
				-- Check if aderyn executable exists
				local aderyn_path = vim.fn.exepath("aderyn")
				if aderyn_path == "" then
					vim.schedule(function()
						vim.notify("aderyn executable not found in PATH", vim.log.levels.ERROR)
					end)
					return {}
				end

				-- Determine working directory - use aderyn_root if set, otherwise project root
				local cwd = config.aderyn_root
				if cwd == "" then
					-- Try to find project root by looking for common Solidity project files
					local root_patterns = { "foundry.toml", "hardhat.config.js", "hardhat.config.ts",
						"truffle-config.js", "package.json" }
					for _, pattern in ipairs(root_patterns) do
						local found = vim.fn.findfile(pattern, ".;")
						if found ~= "" then
							cwd = vim.fn.fnamemodify(found, ":h")
							break
						end
					end
					-- Fallback to current working directory
					if cwd == "" then
						cwd = vim.fn.getcwd()

					end
				end
				vim.notify(string.format("cwd: %s", cwd), vim.log.levels.WARN)

				-- Build command arguments
				local args = {
					"--output", "/tmp/aderyn_output.json", -- JSON output file
				}

				-- Add any extra arguments
				for _, arg in ipairs(config.extra_args) do
					table.insert(args, arg)
				end

				-- Add the root directory to analyze
				table.insert(args, cwd)

				-- Create the full command
				local full_cmd = vim.list_extend({ "aderyn" }, args)

				-- Debug logging
				local f = io.open("/tmp/nvim_aderyn_debug.log", "a")
				if f then
					f:write(string.format("Running: %s\n", vim.fn.join(full_cmd, " ")))
					f:write(string.format("CWD: %s\n", cwd))
					f:close()
				end

				vim.system(
					full_cmd,
					{
						text = true,
						cwd = cwd,
						env = vim.env,
					},
					function(obj)
						local diags_by_file = {}

						-- Read the JSON output file
						local output_file = io.open("/tmp/aderyn_output.json", "r")

						if not output_file then
							vim.schedule(function()
								vim.notify("Failed to read Aderyn output",
									vim.log.levels.ERROR)
							end)
							return
						end

						local json_content = output_file:read("*all")
						output_file:close()

						-- Parse JSON output
						local ok, parsed = pcall(vim.json.decode, json_content)
						if not ok or not parsed then
							vim.schedule(function()
								vim.notify("Failed to parse Aderyn JSON output",
									vim.log.levels.ERROR)
							end)
							return
						end

						-- Debug logging
						local f = io.open("/tmp/nvim_aderyn_debug.log", "a")
						if f then
							f:write("Parsed Aderyn output:\n")
							f:write(vim.inspect(parsed) .. "\n")
							f:close()
						end

						-- Process both high and low severity issues
						local issue_categories = {
							{ issues = parsed.high_issues and parsed.high_issues.issues or {}, severity = "high" },
							{ issues = parsed.low_issues and parsed.low_issues.issues or {},   severity = "low" }
						}

						for _, category in ipairs(issue_categories) do
							local severity = get_severity(category.severity)

							-- Skip if severity is below minimum threshold
							if severity <= config.minimum_severity then
								for _, issue in ipairs(category.issues) do
									for _, instance in ipairs(issue.instances or {}) do
										if is_valid_instance(instance) then
											-- Build the diagnostic message
											local message = string.format(
												"%s: %s [%s]",
												issue.title or
												"Unknown Issue",
												issue.description or "",
												issue.detector_name or
												"unknown"
											)

											-- Add hint if available
											if instance.hint then
												message = message ..
												    "\nHint: " ..
												    instance.hint
											end

											local file_path = instance
											    .contract_path

											-- Convert to absolute path if relative
											if not vim.startswith(file_path, "/") then
												file_path = vim.fn
												    .fnamemodify(
													    cwd ..
													    "/" ..
													    file_path,
													    ":p")
											end

											-- Initialize diagnostics array for this file if needed
											if not diags_by_file[file_path] then
												diags_by_file[file_path] = {}
											end

											local diag = {
												lnum = instance.line_no -
												    1, -- Convert to 0-based indexing
												col = 0, -- Aderyn doesn't provide column info, default to start of line
												end_lnum = instance
												    .line_no - 1,
												end_col = -1, -- End of line
												source = "aderyn",
												message = message,
												severity = severity,
												-- Store additional metadata in user_data
												user_data = {
													detector_name =
													    issue.detector_name,
													issue_title =
													    issue.title,
													issue_description =
													    issue.description,
													issue_severity =
													    category.severity,
													src_char =
													    instance.src_char,
													hint = instance
													    .hint
												}
											}
											table.insert(
												diags_by_file[file_path],
												diag)
										end
									end
								end
							end
						end

						-- Schedule the diagnostic updates for all affected files
						vim.schedule(function()
							local namespace = vim.api.nvim_create_namespace("aderyn-nvim")

							for file_path, diags in pairs(diags_by_file) do
								-- Find the buffer for this file
								local bufnr = vim.fn.bufnr(file_path)
								if bufnr ~= -1 and vim.api.nvim_buf_is_valid(bufnr) then
									vim.diagnostic.set(namespace, bufnr, diags)
								end
							end
						end)

						-- Clean up temporary file
						os.remove("/tmp/aderyn_output.json")
					end
				)

				return {}
			end
		}
	}

	null_ls.register(aderyn_generator)
end

---Show detailed information about the Aderyn issue under the cursor
function M.show_issue_details()
	-- Get the diagnostics under the cursor
	local cursor_pos = vim.api.nvim_win_get_cursor(0)
	local line = cursor_pos[1] - 1
	local col = cursor_pos[2]
	local diagnostics = vim.diagnostic.get(0, {
		namespace = vim.api.nvim_create_namespace("aderyn-nvim"),
		lnum = line
	})

	-- Find the diagnostic at or closest to cursor position
	local current_diagnostic = nil
	for _, diagnostic in ipairs(diagnostics) do
		if diagnostic.lnum == line then
			current_diagnostic = diagnostic
			break
		end
	end

	if not current_diagnostic or not current_diagnostic.user_data then
		vim.notify("No Aderyn diagnostic found under cursor", vim.log.levels.WARN)
		return
	end

	-- Build detailed message
	local details = {
		string.format("**%s**", current_diagnostic.user_data.issue_title or "Unknown Issue"),
		"",
		string.format("**Detector:** %s", current_diagnostic.user_data.detector_name or "N/A"),
		string.format("**Severity:** %s", current_diagnostic.user_data.issue_severity or "N/A"),
		"",
		"**Description:**",
		current_diagnostic.user_data.issue_description or "No description available",
	}

	-- Add hint if available
	if current_diagnostic.user_data.hint then
		table.insert(details, "")
		table.insert(details, "**Hint:**")
		table.insert(details, current_diagnostic.user_data.hint)
	end

	-- Add source character information if available
	if current_diagnostic.user_data.src_char then
		table.insert(details, "")
		table.insert(details, string.format("**Source Location:** %s", current_diagnostic.user_data.src_char))
	end

	-- Show in hover window
	vim.lsp.util.open_floating_preview(
		details,
		'markdown',
		{
			border = "rounded",
			focus = true,
			width = 80,
			height = math.min(#details + 2, 20), -- Limit height
			close_events = { "BufHidden", "BufLeave" },
			focusable = true,
			focus_id = "aderyn_details",
		}
	)
end

return M
