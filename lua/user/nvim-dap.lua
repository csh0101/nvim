local status_ok, dap = pcall(require, "dap")
if not status_ok then
	return
end

local M = {}

require("dap-go").setup()
require("dap.ext.vscode").load_launchjs()

vim.highlight.create("DapBreakpoint", { ctermbg = 0, guifg = "#993939", guibg = "#31353f" }, false)
vim.highlight.create("DapLogPoint", { ctermbg = 0, guifg = "#61afef", guibg = "#31353f" }, false)
vim.highlight.create("DapStopped", { ctermbg = 0, guifg = "#98c379", guibg = "#31353f" }, false)

vim.fn.sign_define(
	"DapBreakpoint",
	{ text = "", texthl = "DapBreakpoint", linehl = "DapBreakpoint", numhl = "DapBreakpoint" }
)
vim.fn.sign_define(
	"DapBreakpointCondition",
	{ text = "ﳁ", texthl = "DapBreakpoint", linehl = "DapBreakpoint", numhl = "DapBreakpoint" }
)
vim.fn.sign_define(
	"DapBreakpointRejected",
	{ text = "", texthl = "DapBreakpoint", linehl = "DapBreakpoint", numhl = "DapBreakpoint" }
)
vim.fn.sign_define(
	"DapLogPoint",
	{ text = "", texthl = "DapLogPoint", linehl = "DapLogPoint", numhl = "DapLogPoint" }
)
vim.fn.sign_define("DapStopped", { text = "", texthl = "DapStopped", linehl = "DapStopped", numhl = "DapStopped" })

dap.adapters.go = function(callback, _)
	local stdout = vim.loop.new_pipe(false)
	local handle
	local pid_or_err
	local port = 38697
	local opts = {
		stdio = { nil, stdout },
		args = { "dap", "-l", "127.0.0.1:" .. port },
		detached = true,
	}
	handle, pid_or_err = vim.loop.spawn("dlv", opts, function(code)
		stdout:close()
		handle:close()
		if code ~= 0 then
			print("dlv exited with code", code)
		end
	end)
	assert(handle, "Error running dlv: " .. tostring(pid_or_err))
	stdout:read_start(function(err, chunk)
		assert(not err, err)
		if chunk then
			vim.schedule(function()
				require("dap.repl").append(chunk)
			end)
		end
	end)
	-- Wait for delve to start
	vim.defer_fn(function()
		callback({ type = "server", host = "127.0.0.1", port = port })
	end, 100)
end

-- auto start and close ui
local ok, dapui = pcall(require, "dapui")
if not ok then
	return
end

local keymap = vim.api.nvim_set_keymap
local function keybind()
	keymap("n", "c", '<cmd>lua require"dap".continue()<CR>', { noremap = true, silent = true })
	keymap("n", "n", '<cmd>lua require"dap".step_over()<CR>', { noremap = true, silent = true })
	keymap("n", "s", '<cmd>lua require"dap".step_into()<CR>', { noremap = true, silent = true })
	keymap("n", "o", '<cmd>lua require"dap".step_out()<CR>', { noremap = true, silent = true })
	keymap("n", "u", '<cmd>lua require"dap".up()<CR>', { noremap = true, silent = true })
	keymap("n", "D", '<cmd>lua require"dap".down()<CR>', { noremap = true, silent = true })
	keymap("n", "C", '<cmd>lua require"dap".run_to_cursor()<CR>', { noremap = true, silent = true })
	keymap("n", "b", '<cmd>lua require"dap".toggle_breakpoint()<CR>', { noremap = true, silent = true })
	keymap("n", "P", '<cmd>lua require"dap".pause()<CR>', { noremap = true, silent = true })
end

local unbind = function()
	local keys = {
		"c",
		"n",
		"s",
		"o",
		"u",
		"D",
		"C",
		"b",
		"P",
	}
	for _, value in pairs(keys) do
		local cmd = "silent! unmap " .. value
		vim.cmd(cmd)
	end
	vim.cmd([[silent! vunmap p]])
end

dap.listeners.after.event_initialized["dapui_config"] = function()
	keybind()
	dapui.open()
end
dap.listeners.before.event_terminated["dapui_config"] = function()
	unbind()
	dapui.close()
end
dap.listeners.before.event_exited["dapui_config"] = function()
	unbind()
	dapui.close()
end
require("dap").listeners.before["event_initialized"]["custom"] = function(_, _)
	keybind()
	require("dapui").open()
end
require("dap").listeners.before["event_terminated"]["custom"] = function(_, _)
	unbind()
	require("dapui").close()
end

dapui.setup({
	icons = { expanded = "▾", collapsed = "▸" },
	mappings = {
		-- Use a table to apply multiple mappings
		expand = { "<CR>", "<2-LeftMouse>", "h", "l" },
		open = "o",
		remove = "d",
		edit = "e",
		repl = "r",
	},
	sidebar = {
		-- You can change the order of elements in the sidebar
		elements = {
			-- Provide as ID strings or tables with "id" and "size" keys
			{
				id = "scopes",
				size = 0.25, -- Can be float or integer > 1
			},
			{ id = "breakpoints", size = 0.25 },
			{ id = "stacks", size = 0.25 },
			{ id = "watches", size = 0.25 },
		},
		size = 40,
		position = "left", -- Can be "left", "right", "top", "bottom"
	},
	tray = {
		elements = { "repl" },
		size = 10,
		position = "bottom", -- Can be "left", "right", "top", "bottom"
	},
	floating = {
		max_height = nil, -- These can be integers or a float between 0 and 1.
		max_width = nil, -- Floats will be treated as percentage of your screen.
		border = "single", -- Border style. Can be "single", "double" or "rounded"
		mappings = {
			close = { "q", "<Esc>" },
		},
	},
	windows = { indent = 1 },
})

local default_launch_json = [[
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Launch main",
      "type": "go",
      "request": "launch",
      "mode": "exec",
      "remotePath": "",
      "program": "${workspaceFolder}/main.go",
      "env": {},
      "args": [],
      "cwd": "${workspaceFolder}",
      "envFile": "${workspaceFolder}/.env",
      "buildFlags": ""
    }
  ]
}

]]

function M.debug_config()
	local resolved_path = vim.fn.getcwd() .. "/.vscode/launch.json"
	if vim.loop.fs_stat(resolved_path) then
		return vim.cmd("e " .. resolved_path)
	end
  vim.fn.mkdir(vim.fn.getcwd() .. "/.vscode/")
  local contents = vim.fn.split(default_launch_json, "\n")
  vim.fn.writefile(contents, resolved_path)
	vim.cmd("e " .. resolved_path)
end

vim.cmd([[ command! DebugConfig execute 'lua require("user.nvim-dap").debug_config()']])

return M
