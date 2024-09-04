local Path = require 'plenary.path'
local Scan = require 'plenary.scandir'
local Job = require 'plenary.job'
local api = vim.api

local M = {}

-- BUFFER_STATE.ORIGIN refers to the buffer where the user invoked the plugin.
-- BUFFER_STATE.SCRATCH is a temporary buffer for debugging/chat.
local BUFFER_STATE = {
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

M.TEMPLATE_DIRECTORY = vim.fn.stdpath 'data' .. '/lazy/kznllm/templates'

local group = api.nvim_create_augroup('LLM_AutoGroup', { clear = true })

---Renders a prompt template using minijinja-cli and returns the rendered lines
---
---@param prompt_template_path Path an absolute path to a jinja file
---@param prompt_args table typically PROMPT_ARGS_STATE which needs to be json encoded
---@return string rendered_prompt
function M.make_prompt_from_template(prompt_template_path, prompt_args)
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
local function write_content_at_extmark(content, extmark_id)
  local extmark = api.nvim_buf_get_extmark_by_id(0, M.NS_ID, extmark_id, { details = false })
  local mrow, mcol = extmark[1], extmark[2]

  vim.cmd 'undojoin'

  local lines = vim.split(content, '\n')
  api.nvim_buf_set_text(0, mrow, mcol, mrow, mcol, lines)
end

---Creates a buffer in markdown mode (for syntax highlighting) and returns an extmark for streaming output
---
---@return integer extmark_id
local function make_scratch_buffer()
  if BUFFER_STATE.SCRATCH then
    api.nvim_buf_delete(BUFFER_STATE.SCRATCH, { force = true })
    BUFFER_STATE.SCRATCH = nil
  end

  BUFFER_STATE.SCRATCH = api.nvim_create_buf(true, false)

  api.nvim_buf_set_name(BUFFER_STATE.SCRATCH, 'debug.md')
  api.nvim_set_option_value('buflisted', true, { buf = BUFFER_STATE.SCRATCH })
  api.nvim_set_option_value('filetype', 'markdown', { buf = BUFFER_STATE.SCRATCH })

  api.nvim_set_current_buf(BUFFER_STATE.SCRATCH)
  api.nvim_set_option_value('wrap', true, { win = 0 })
  api.nvim_set_option_value('linebreak', true, { win = 0 })
  api.nvim_set_option_value('breakindent', true, { win = 0 })

  local num_lines = api.nvim_buf_line_count(BUFFER_STATE.SCRATCH)
  api.nvim_win_set_cursor(0, { num_lines, 0 })

  local extmark_id = api.nvim_buf_set_extmark(BUFFER_STATE.SCRATCH, M.NS_ID, 0, 0, {})

  -- Set up key mapping to close the buffer
  api.nvim_buf_set_keymap(BUFFER_STATE.SCRATCH, 'n', '<leader>q', '', {
    noremap = true,
    silent = true,
    callback = function()
      -- Trigger the LLM_Escape event
      api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })

      api.nvim_buf_call(BUFFER_STATE.SCRATCH, function()
        vim.cmd 'bdelete!'
        BUFFER_STATE.SCRATCH = nil
      end)
    end,
  })

  return extmark_id
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
---@return integer stream_end_extmark_id this extmark determines where to stream output tokens
---@return string visual_selection returns the full selection
function M.get_visual_selection(opts)
  local mode = api.nvim_get_mode().mode
  BUFFER_STATE.ORIGIN = api.nvim_win_get_buf(0)

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
  local stream_end_extmark_id, visual_selection
  local replace_mode = not (mode == 'n')
  local debug = opts and opts.debug

  if replace_mode then
    api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
    visual_selection = table.concat(api.nvim_buf_get_text(BUFFER_STATE.ORIGIN, srow, scol, erow, ecol, {}), '\n')
    stream_end_extmark_id = api.nvim_buf_set_extmark(BUFFER_STATE.ORIGIN, M.NS_ID, erow, ecol, {})
  else
    -- put an extmark at the beginning of the line if there's nothing to replace
    stream_end_extmark_id = api.nvim_buf_set_extmark(BUFFER_STATE.ORIGIN, M.NS_ID, erow, 0, {})
  end

  if not debug and replace_mode then
    api.nvim_buf_set_text(BUFFER_STATE.ORIGIN, srow, scol, erow, ecol, {})
  end

  return stream_end_extmark_id, visual_selection
end

---Locates the path value for context directory
---
---@param opts { stop_dir: Path, context_dir_id: string } optional values including `stop_dir` that is the Path value to specify when to stop scanning for a valid context directory identifier `context_dir_id`
---@return Path context_dir directory path
function M.find_context_directory(opts)
  local context_dir_id, context_dir

  local stop_dir = opts and opts.stop_dir or Path:new(vim.fn.expand '~')

  context_dir_id = opts and opts.context_dir_id or '.kzn'
  context_dir = Path:new(vim.fn.getcwd())

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
---@param opts table optional values including stop directory to prevent scanning beyond it
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
  buf_id = buf_id or BUFFER_STATE.ORIGIN

  local buf_filetype, buf_path, buf_context
  buf_filetype = vim.bo.filetype
  buf_path = api.nvim_buf_get_name(buf_id)
  buf_context = table.concat(api.nvim_buf_get_lines(buf_id, 0, -1, false), '\n')

  return buf_filetype, buf_path, buf_context
end

--- Invokes an LLM via a supported API spec in "inline" mode
---
--- Must provide the function for constructing cURL arguments and a handler
--- function for processing server-sent events.
---
---@param prompt_messages { role: string, prompt_template: string, args: table }[]
---@param make_job_fn fun(rendered_message: { role: string, content: string }, writer_fn: fun(content: string), on_exit_fn: fun())
function M.invoke_llm(prompt_messages, make_job_fn, opts)
  if vim.fn.executable 'minijinja-cli' ~= 1 then
    error("Can't find minijinja-cli, download it from https://github.com/mitsuhiko/minijinja or add it to $PATH", 1)
  end

  api.nvim_clear_autocmds { group = group }

  local active_job

  BUFFER_STATE.ORIGIN = api.nvim_win_get_buf(0)
  M.get_user_input(function()
    M.PROMPT_ARGS_STATE.replace = not (api.nvim_get_mode().mode == 'n')

    local stream_end_extmark_id, visual_selection = M.get_visual_selection(opts)
    M.PROMPT_ARGS_STATE.visual_selection = visual_selection

    local context_dir = M.find_context_directory(opts)
    if context_dir then
      M.PROMPT_ARGS_STATE.context_files = M.get_project_files(context_dir, opts)
    end

    -- don't update current context when in debug mode
    if BUFFER_STATE.SCRATCH == nil then
      -- similar to rendering a template, but we want to get the context of the file without relying on the changes being saved
      local buf_filetype, buf_path, buf_context = M.get_buffer_context(BUFFER_STATE.ORIGIN, opts)
      M.PROMPT_ARGS_STATE.current_buffer_filetype = buf_filetype
      M.PROMPT_ARGS_STATE.current_buffer_path = buf_path
      M.PROMPT_ARGS_STATE.current_buffer_context = buf_context
    end

    -- render context
    local debug = opts and opts.debug
    local rendered_messages = {}

    if debug then
      stream_end_extmark_id = make_scratch_buffer()
    end

    for _, message in ipairs(prompt_messages) do
      local template_path = Path:new(M.TEMPLATE_DIRECTORY) / message.prompt_template

      if not template_path:exists() then
        error(string.format('could not find template at %s', template_path), 1)
      end

      table.insert(rendered_messages, { role = message.role, content = make_prompt_from_template(template_path:absolute(), M.PROMPT_ARGS_STATE) })

      if debug then
        write_content_at_extmark(message.role .. ':\n\n', stream_end_extmark_id)
        write_content_at_extmark(make_prompt_from_template(template_path:absolute(), M.PROMPT_ARGS_STATE), stream_end_extmark_id)
        write_content_at_extmark('\n\n---\n\n', stream_end_extmark_id)
        vim.cmd 'normal! G'
      end
    end

    active_job = make_job_fn(rendered_messages, function(content)
      write_content_at_extmark(content, stream_end_extmark_id)
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

api.nvim_set_keymap('n', '<Esc>', '', {
  noremap = true,
  silent = true,
  callback = function()
    api.nvim_exec_autocmds('User', { pattern = 'LLM_Escape' })
  end,
})

return M
