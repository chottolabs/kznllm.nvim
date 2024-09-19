local Path = require 'plenary.path'
local Scan = require 'plenary.scandir'
local Job = require 'plenary.job'
local api = vim.api

local M = {}

---Renders a prompt template using minijinja-cli and returns the rendered lines
---
---@param prompt_template_path Path absolute path to a jinja file
---@param prompt_args table typically PROMPT_ARGS_STATE which needs to be json encoded
---@return string rendered_prompt
function M.make_prompt_from_template(prompt_template_path, prompt_args)
  if vim.fn.executable 'minijinja-cli' ~= 1 then
    error("Can't find minijinja-cli, download it from https://github.com/mitsuhiko/minijinja or add it to $PATH", 1)
  end

  if not prompt_template_path:exists() then
    error(string.format('could not find template at %s', prompt_template_path), 1)
  end

  local json_data = vim.json.encode(prompt_args)
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

---@param content string
---@param extmark_id integer
function M.write_content_at_extmark(content, ns_id, extmark_id)
  local extmark = api.nvim_buf_get_extmark_by_id(0, ns_id, extmark_id, { details = false })
  local mrow, mcol = extmark[1], extmark[2]

  local lines = vim.split(content, '\n')

  vim.cmd 'undojoin'
  api.nvim_buf_set_text(0, mrow, mcol, mrow, mcol, lines)
end

---Creates a buffer in markdown mode (for syntax highlighting)
function M.make_scratch_buffer()
  local buf_id = api.nvim_create_buf(true, false)

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
--- @param on_submit function callback function to call when user submits input
function M.get_user_input(on_submit)
  vim.ui.input({ prompt = 'prompt: ' }, function(input)
    if input ~= nil then
      on_submit(input)
    end
  end)
end

---Handles visual selection depending on the specified mode and some expected states of the user's current buffer.
--- Returns an appropriate position to stream output tokens and
---
---@param opts table optional values including debug mode
---@return string visual_selection returns the full selection
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

  return visual_selection, srow, scol, erow, ecol
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
---@param context_dir Path
---@param opts table optional values
---@return string[] context_files list of files in the context directory
function M.get_project_files(context_dir, opts)
  local context_files = Scan.scan_dir(context_dir:absolute(), { hidden = false })
  vim.print('using context at: ' .. context_dir:absolute())
  local context = {}
  for _, file in ipairs(context_files) do
    table.insert(context, { path = file, content = Path:new(file):read() })
  end

  return context
end

---similar to rendering a template, but we want to get the context of the file without relying on the changes being saved
---@param buf_id integer the id of the buffer to retrieve context for
---@param opts table optional values to pass to the function
---@return string buf_filetype the filetype of the buffer
---@return string buf_path the path of the buffer
---@return string buf_context the context of the buffer
function M.get_buffer_context(buf_id, opts)
  local buf_filetype, buf_path, buf_context
  buf_filetype = vim.bo.filetype
  buf_path = api.nvim_buf_get_name(buf_id)
  buf_context = table.concat(api.nvim_buf_get_lines(buf_id, 0, -1, false), '\n')

  return buf_filetype, buf_path, buf_context
end

--- Makes a no-op change to the buffer at the specified extmark.
--- This is used before making changes to avoid calling undojoin after undo.
---
---@param extmark_id integer the id of the extmark
function M.noop(ns_id, extmark_id)
  local extmark = api.nvim_buf_get_extmark_by_id(0, ns_id, extmark_id, { details = false })
  local mrow, mcol = extmark[1], extmark[2]
  api.nvim_buf_set_text(0, mrow, mcol, mrow, mcol, {})
end

return M
