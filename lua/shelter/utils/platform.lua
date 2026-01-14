---Platform-specific utilities for shelter.nvim
---@module "shelter.utils.platform"

local M = {}

---Get the platform-specific library filename for the native module.
---@return string lib_name The library filename (e.g., "libshelter_core.dylib")
function M.get_library_name()
	local uname = vim.uv.os_uname()
	return uname.sysname == "Darwin" and "libshelter_core.dylib"
		or uname.sysname == "Windows" and "shelter_core.dll"
		or "libshelter_core.so"
end

---Get the library names table indexed by platform.
---@return table<string, string> lib_names Platform-to-library mapping
function M.get_library_names()
	return {
		Darwin = "libshelter_core.dylib",
		Linux = "libshelter_core.so",
		Windows = "shelter_core.dll",
	}
end

return M
