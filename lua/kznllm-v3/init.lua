local Path = require 'plenary.path'
local Scan = require 'plenary.scandir'
local Job = require 'plenary.job'
local api = vim.api
local uv = vim.uv

local M = {}

--
-- [ CONTEXT BUILDING UTILITY FUNCTIONS ]
--

function M.get_user_input()
  local value
  vim.ui.input({ prompt = 'prompt: ' }, function(input)
    value = input
  end)
  return value
end

---Handles visual selection depending on the specified mode and some expected states of the user's current buffer.
--- Returns an appropriate position to stream output tokens and
---
---@param opts { debug: boolean? } optional values including debug mode
---@return string selection
function M.get_visual_selection(opts)
  local mode = api.nvim_get_mode().mode

  -- get visual selection and current cursor position (1-indexed)
  local _, srow, scol = unpack(vim.fn.getpos 'v')
  local _, erow, ecol = unpack(vim.fn.getpos '.')

  -- normalize start + end such that start_pos < end_pos and converts to 0-index
  srow, scol, erow, ecol = srow - 1, scol - 1, erow - 1, ecol - 1
  if srow > erow or (srow == erow and scol > ecol) then
    srow, erow, scol, ecol = erow, srow, ecol, scol
  end

  -- in visual block and visual line mode, we expect first column of srow and last column of erow
  if mode == 'V' or mode == '\22' or mode == 'n' then
    scol, ecol = 0, -1
  else
    local erow_content = vim.api.nvim_buf_get_lines(0, erow, erow + 1, false)[1]
    if ecol < #erow_content then
      ecol = ecol + 1
    end
  end

  -- handling + cleanup for visual selection
  local visual_selection
  local replace_mode = not (mode == 'n')

  if replace_mode then
    api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
    visual_selection = table.concat(api.nvim_buf_get_text(0, srow, scol, erow, ecol, {}), '\n')
  end

  -- clear the visual selection depending on condition
  local debug = opts and opts.debug
  if not debug and replace_mode then
    api.nvim_buf_set_text(0, srow, scol, erow, ecol, {})
  end

  return visual_selection
end

---Locates the path value for context directory
---
---@param opts { stop_dir: Path?, context_dir_id: string? } `stop_dir` - Path to stop traversing directories (default `$HOME`, `context_dir_id` - identifier that this function will scan for (default `.kzn`)
---@return Path context_dir directory path
function M.find_context_directory(opts)
  local stop_dir = opts and opts.stop_dir or Path:new(vim.fn.expand '~')
  local context_dir_id = opts and opts.context_dir_id or '.kzn'
  local context_dir = Path:new(vim.fn.getcwd())

  while not (context_dir / context_dir_id):exists() and context_dir:is_dir() do
    if context_dir:absolute() == stop_dir:absolute() then
      context_dir = nil
      break
    end

    context_dir = context_dir:parent()
  end

  if context_dir then
    context_dir = context_dir / context_dir_id
  end

  return context_dir
end
---project scoped context
---
---Retrieves project files based on the context directory identifier and the current working directory.
---
---@param opts { stop_dir: Path, context_dir_id: string } values
---@return { path: string, content: string }? context_files list of files in the context directory
function M.get_project_files(opts)
  local context_dir = M.find_context_directory({
    stop_dir = Path:new(vim.fn.expand '~'),
    context_dir_id = '.kzn'
  })

  if context_dir == nil then
    return nil
  end

  vim.print('using context at: ' .. context_dir:absolute())
  local context = {}
  local function scan_dir(dir)
    Scan.scan_dir(
      dir,
      {
        hidden = false,
        on_insert = function (file, typ)
          if typ == 'link' then
            file = vim.fn.resolve(file)
            if uv.fs_stat(file).type == "directory" then
              scan_dir(file)
              return
            end
          end

          local path = Path:new(file)
          table.insert(context, { path = path:absolute(), content = path:read() })
        end
      }
    )
  end
  scan_dir(context_dir:absolute())

  return context
end

return M
