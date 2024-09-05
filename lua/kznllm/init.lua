local Path = require 'plenary.path'
local Scan = require 'plenary.scandir'
local Job = require 'plenary.job'
local api = vim.api

local M = {}

-- ORIGIN refers to the buffer where the user invoked the plugin.
-- SCRATCH is a temporary buffer for debugging/chat.
M.BUFFER_STATE = {
  SCRATCH = nil,
  ORIGIN = nil,
}

M.PROMPT_ARGS_STATE = {
  current_buffer_path = nil,
  current_buffer_context = nil,
  current_buffer_filetype = nil,
  visual_selection = nil,
  user_query = nil,
  replace = nil,
  context_files = nil,
}

M.NS_ID = api.nvim_create_namespace 'kznllm_ns'

local group = api.nvim_create_augroup('LLM_AutoGroup', { clear = true })

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
    args = { '-f', 'json', prompt_template_path:absolute(), '-' },
    writer = json_data,
    on_stderr = function(message, _)
      error(message, 1)
    end,
  }

  active_job:sync()
  return table.concat(active_job:result(), '\n')
end

---@param content string
---@param extmark_id integer
function M.write_content_at_extmark(content, extmark_id)
  local extmark = api.nvim_buf_get_extmark_by_id(0, M.NS_ID, extmark_id, { details = false })
  local mrow, mcol = extmark[1], extmark[2]

  local lines = vim.split(content, '\n')

  -- Check if there are any pending changes in the buffer
  local undo_sequence_active = vim.bo.modified

  -- Use 'undojoin' only if an undo sequence is active
  if undo_sequence_active then
    vim.cmd 'undojoin'
  end
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

  -- Set up key mapping to close the buffer
  api.nvim_buf_set_keymap(buf_id, 'n', '<leader>q', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Trigger the LLM_Escape event
      api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })

      api.nvim_buf_call(buf_id, function()
        vim.cmd 'bdelete!'
      end)
    end,
  })
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
      M.PROMPT_ARGS_STATE.user_query = input
      on_submit()
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
  M.BUFFER_STATE.ORIGIN = api.nvim_win_get_buf(0)

  -- get visual selection and current cursor position (1-indexed)
  local _, srow, scol = unpack(vim.fn.getpos 'v')
  local _, erow, ecol = unpack(vim.fn.getpos '.')

  -- normalize start + end such that start_pos < end_pos and converts to 0-index
  srow, scol, erow, ecol = srow - 1, scol - 1, erow - 1, ecol - 1
  if srow > erow then
    srow, erow = erow, srow
  end

  if scol > ecol then
    scol, ecol = ecol, scol
  end

  -- in visual block and visual line mode, we expect first column of srow and last column of erow
  if mode == 'V' or mode == '\22' or mode == 'n' then
    scol, ecol = 0, -1
  else
    ecol = ecol + 1
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
---@param context_dir Path
---@param opts table optional values
---@return string[] context_files list of files in the context directory
function M.get_project_files(context_dir, opts)
  local context_files = Scan.scan_dir(context_dir:absolute(), { hidden = false })
  vim.print('using context at: ' .. context_dir:absolute())

  return context_files
end

---similar to rendering a template, but we want to get the context of the file without relying on the changes being saved
---@param buf_id integer the id of the buffer to retrieve context for
---@param opts table optional values to pass to the function
---@return string buf_filetype the filetype of the buffer
---@return string buf_path the path of the buffer
---@return string buf_context the context of the buffer
function M.get_buffer_context(buf_id, opts)
  buf_id = buf_id or M.BUFFER_STATE.ORIGIN

  local buf_filetype, buf_path, buf_context
  buf_filetype = vim.bo.filetype
  buf_path = api.nvim_buf_get_name(buf_id)
  buf_context = table.concat(api.nvim_buf_get_lines(buf_id, 0, -1, false), '\n')

  return buf_filetype, buf_path, buf_context
end

--- Working implementation of "inline" fill mode
--- Invokes an LLM via a supported API spec defined by
---
--- Must provide the function for constructing cURL arguments and a handler
--- function for processing server-sent events.
---
---@param make_data_fn fun(prompt_args: table, opts: table)
---@param make_curl_args_fn fun(data: table, opts: table)
---@param make_job_fn fun(data: table, writer_fn: fun(content: string), on_exit_fn: fun())
---@param opts { debug: string?, debug_fn: fun(data: table, extmark_id: integer, opts: table)?, stop_dir: Path?, context_dir_id: string? }
function M.invoke_llm(make_data_fn, make_curl_args_fn, make_job_fn, opts)
  api.nvim_clear_autocmds { group = group }

  local active_job

  M.BUFFER_STATE.ORIGIN = api.nvim_win_get_buf(0)

  M.get_user_input(function()
    M.PROMPT_ARGS_STATE.replace = not (api.nvim_get_mode().mode == 'n')

    local visual_selection = M.get_visual_selection(opts)
    M.PROMPT_ARGS_STATE.visual_selection = visual_selection

    local context_dir = M.find_context_directory(opts)
    if context_dir then
      M.PROMPT_ARGS_STATE.context_files = M.get_project_files(context_dir, opts)
    end

    -- don't update current context when in debug mode
    if M.BUFFER_STATE.SCRATCH == nil then
      -- similar to rendering a template, but we want to get the context of the file without relying on the changes being saved
      local buf_filetype, buf_path, buf_context = M.get_buffer_context(M.BUFFER_STATE.ORIGIN, opts)
      M.PROMPT_ARGS_STATE.current_buffer_filetype = buf_filetype
      M.PROMPT_ARGS_STATE.current_buffer_path = buf_path
      M.PROMPT_ARGS_STATE.current_buffer_context = buf_context
    end

    local data = make_data_fn(M.PROMPT_ARGS_STATE, opts)

    local stream_end_extmark_id

    -- open up scratch buffer before setting extmark
    if opts and opts.debug and opts.debug_fn then
      if M.BUFFER_STATE.SCRATCH then
        api.nvim_buf_delete(M.BUFFER_STATE.SCRATCH, { force = true })
        M.BUFFER_STATE.SCRATCH = nil
      end
      M.BUFFER_STATE.SCRATCH = M.make_scratch_buffer()

      stream_end_extmark_id = api.nvim_buf_set_extmark(M.BUFFER_STATE.SCRATCH, M.NS_ID, 0, 0, {})
      opts.debug_fn(data, stream_end_extmark_id, opts)
    else
      local _, crow, ccol = unpack(vim.fn.getpos '.')
      stream_end_extmark_id = api.nvim_buf_set_extmark(M.BUFFER_STATE.ORIGIN, M.NS_ID, crow - 1, ccol - 1, {})
    end

    local args = make_curl_args_fn(data, opts)

    active_job = make_job_fn(args, function(content)
      M.write_content_at_extmark(content, stream_end_extmark_id)
    end, function()
      api.nvim_buf_del_extmark(0, M.NS_ID, stream_end_extmark_id)
    end)

    active_job:start()

    api.nvim_create_autocmd('User', {
      group = group,
      pattern = 'LLM_Escape',
      callback = function()
        if active_job.is_shutdown ~= true then
          active_job:shutdown()
          print 'LLM streaming cancelled'
        end
      end,
    })
  end)
end

return M
