local util = require("lspconfig/util")
-- NOTE: this is set on the nixos side, by the vscode module.
local server = vim.env.HOME .. "/.vscode/extensions/pylance/dist/server.bundle.js"
local cmd = { "node", server, "--stdio" }
return {
	default_config = {
		name = "pylance",
		autostart = true,
		cmd = cmd,
		filetypes = { "python" },
		root_dir = function(fname)
			local markers = {
				"Pipfile",
				"pyproject.toml",
				"pyrghtconfig.json",
				"setup.py",
				"setup.cfg",
				"requirements.txt",
				"poetry.toml",
				".git/",
			}

			-- TODO: find alternative to unpack, get deprecated warning in lua 5.1 and we are using 5.4
			-- NOTE:: unpack was moved to table.unpack() : https://www.lua.org/manual/5.2/manual.html
			-- (8.2 - Changes in the Libraries):  Function unpack was moved into the table library and
			-- therefore must be called as table.unpack.
			return util.root_pattern(table.unpack(markers))(fname)
				or util.find_git_ancestor(fname)
				or util.path.dirname(fname)
		end,
		settings = {
			python = {
				telemetry = {
					telemetryLevel = "off",
				},
				analysis = {
					typeCheckingMode = "strict",
					diagnosticMode = "workspace",
					stubPath = "./typings",
					autoSearchPaths = true,
					extraPaths = {},
					diagnosticSeverityOverrides = {},
					useLibraryCodeForTypes = true,
					autoImportCompletions = true,
					variableTypes = true,
					functionReturnTypes = true,
					enablePytestSupport = true,
					autoFormatStrings = true,
					inlayHints = {
						variableTypes = true,
						functionReturnTypes = true,
						pytestParameters = true,
					},
				},
			},
		},
		-- docs = {
		--   package_jon = vim.env.HOME .. "/.vscode/extensions/"
		-- }
	},
}

-- TODO: integrate the rest of this code into the config.
-- https://github.com/microsoft/pylance-release
--
-- local util = require("lspconfig.util")
--
-- local get_script_path = function()
--     local scripts =
--         vim.fn.expand("$HOME/.vscode/extensions/ms-python.vscode-pylance-*/dist/server.bundle.js", false, true)
--
--     -- After an upgrade the old plugin might linger for a while.
--     table.sort(scripts, function(a, b)
--         return a > b
--     end)
--
--     if scripts[1] == nil then
--         error("Failed to resolve path to Pylance server")
--     end
--
--     return scripts[1]
-- end
--
-- local cmd = { "node", get_script_path(), "--stdio" }
--
-- return {
--     default_config = {
--         name = "pylance",
--         autostart = true,
--         filetypes = { "python" },
--         root_dir = function(fname)
--             local markers = {
--                 "Pipfile",
--                 "pyproject.toml",
--                 "pyrightconfig.json",
--                 "setup.py",
--                 "setup.cfg",
--                 "requirements.txt",
--             }
--             return util.root_pattern(unpack(markers))(fname) or util.find_git_ancestor(fname)
--                 or util.path.dirname(fname)
--         end,
--         settings = {
--             python = {
--                 analysis = vim.empty_dict(),
--             },
--             telemetry = {
--                 telemetryLevel = "off",
--             },
--         },
--         docs = {
--             package_json = vim.fn.expand(
--                 "$HOME/.vscode/extensions/ms-python.vscode-pylance-*/package.json",
--                 false,
--                 true
--             )[1],
--             description = [[
--       https://github.com/microsoft/pyright
--       `pyright`, a static type checker and language server for python
--       ]],
--         },
--     },
-- }
