local Path = require 'plenary.path'
local Job = require 'plenary.job'
local Scan = require 'plenary.scandir'
local api = vim.api
local uv = vim.uv

local M = {}

-- NOTE: this is a relative path meant to point at the template directory
local plugin_dir = Path:new(debug.getinfo(1, 'S').source:sub(2)):parents()[3]
M.TEMPLATE_PATH = Path:new(plugin_dir) / 'templates'

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
--- Returns the selection and whether or not text was replaced
---
---@param opts { debug: boolean? } optional values including debug mode
---@return string selection
---@return boolean replace
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

  return visual_selection, replace_mode
end

---Locates the path value for context directory
---
---@param opts { stop_dir: Path?, context_dir_id: string? } `stop_dir` - Path to stop traversing directories (default `$HOME`, `context_dir_id` - identifier that this function will scan for (default `.kzn`)
---@return Path? context_dir directory path
function M.find_context_directory(opts)
  local stop_dir = opts and opts.stop_dir or Path:new(vim.fn.expand '~')
  local context_dir_id = opts and opts.context_dir_id or '.kzn'

  local cur_buf_dir = Path:new(vim.api.nvim_buf_get_name(0)):parent()
  local context_dir = Path:new(vim.fn.getcwd())

  while not (context_dir / context_dir_id):exists() and context_dir:is_dir() do
    if context_dir:absolute() == stop_dir:absolute() then
      return nil
    end

    context_dir = context_dir:parent()
  end

  return context_dir / context_dir_id
end

---project scoped context
---
---Retrieves project files based on the context directory identifier and the current working directory.
---
---@param opts { stop_dir: Path, context_dir_id: string } values
---@return { path: string, content: string }? context_files list of files in the context directory
function M.get_project_files(opts)
  local context_dir = M.find_context_directory(opts)
  if context_dir then
    vim.print('using context at: ' .. context_dir:absolute())
    local context = {}
    local function scan_dir(dir)
      Scan.scan_dir(dir, {
        hidden = false,
        on_insert = function(file, typ)
          if typ == 'link' then
            file = vim.fn.resolve(file)
            if uv.fs_stat(file).type == 'directory' then
              scan_dir(file)
              return
            end
          end

          local path = Path:new(file)
          table.insert(context, { path = path:absolute(), content = path:read() })
        end,
      })
    end
    scan_dir(context_dir:absolute())

    return context
  end
end

---Creates a prompt from template
---@param opts { template_path: Path, filename: string, prompt_args: table }
---@return string
function M.make_prompt_from_template(opts)
  if vim.fn.executable 'minijinja-cli' ~= 1 then
    error("Can't find minijinja-cli, download it from https://github.com/mitsuhiko/minijinja or add it to $PATH", 1)
  end

  local prompt_template_path = opts.template_path / opts.filename

  if not prompt_template_path:exists() then
    error(string.format('could not find template at %s', prompt_template_path), 1)
  end

  local json_data = vim.json.encode(opts.prompt_args)
  local active_job = Job:new {
    command = 'minijinja-cli',
    args = { '-f', 'json', '--lstrip-blocks', '--trim-blocks', prompt_template_path:absolute(), '-' },
    writer = json_data,
  }

  active_job:sync()
  if active_job.code ~= 0 then
    local error_msg = table.concat(active_job:stderr_result(), '\n')
    error('[minijinja-cli] (exit code: ' .. active_job.code .. ')\n' .. error_msg, vim.log.levels.ERROR)
  end

  return table.concat(active_job:result(), '\n')
end

return M
