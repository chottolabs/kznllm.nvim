local Path = require 'plenary.path'
local Scan = require 'plenary.scandir'
local Job = require 'plenary.job'
local api = vim.api
local uv = vim.uv

local M = {}

---Renders a prompt template using minijinja-cli and returns the rendered lines
---
---@param opts { prompt_template_path:Path, prompt_args:table } absolute path to a jinja file, typically PROMPT_ARGS_STATE which needs to be json encoded
---@return string rendered_prompt
function M.make_prompt_from_template(opts)
  if vim.fn.executable 'minijinja-cli' ~= 1 then
    error("Can't find minijinja-cli, download it from https://github.com/mitsuhiko/minijinja or add it to $PATH", 1)
  end

  if not opts.prompt_template_path:exists() then
    error(string.format('could not find template at %s', opts.prompt_template_path), 1)
  end

  local json_data = vim.json.encode(opts.prompt_args)
  local active_job = Job:new {
    command = 'minijinja-cli',
    args = { '-f', 'json', '--lstrip-blocks', '--trim-blocks', opts.prompt_template_path:absolute(), '-' },
    writer = json_data,
  }

  active_job:sync()
  if active_job.code ~= 0 then
    local error_msg = table.concat(active_job:stderr_result(), '\n')
    error('[minijinja-cli] (exit code: ' .. active_job.code .. ')\n' .. error_msg, vim.log.levels.ERROR)
  end

  return table.concat(active_job:result(), '\n')
end

---Creates a buffer in markdown mode (for syntax highlighting)
function M.make_scratch_buffer()
  local buf_id = api.nvim_create_buf(false, true)

  -- api.nvim_set_option_value('buflisted', true, { buf = buf_id })
  api.nvim_set_option_value('filetype', 'markdown', { buf = buf_id })
  api.nvim_set_option_value('swapfile', false, { buf = buf_id })

  api.nvim_set_current_buf(buf_id)
  api.nvim_set_option_value('wrap', true, { win = 0 })
  api.nvim_set_option_value('linebreak', true, { win = 0 })
  api.nvim_set_option_value('breakindent', true, { win = 0 })

  local num_lines = api.nvim_buf_line_count(buf_id)
  api.nvim_win_set_cursor(0, { num_lines, 0 })
  return buf_id
end

--
-- [ CONTEXT BUILDING UTILITY FUNCTIONS ]
--

--- Gets user input and returns it.
---
function M.get_user_input()
  local value
  vim.ui.input({ prompt = 'prompt: ' }, function(input)
    if input ~= nil then
      value = input
    end
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

--- Makes a no-op change to the buffer at the specified extmark.
--- This is used before making changes to avoid calling undojoin after undo.
function M.noop()
  api.nvim_buf_set_text(0, 0, 0, 0, 0, {})
end

return M
