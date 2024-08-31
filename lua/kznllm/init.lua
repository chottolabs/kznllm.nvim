local Path = require 'plenary.path'
local Scan = require 'plenary.scandir'
local Job = require 'plenary.job'

-- ORIGIN refers to the buffer where the user invoked the plugin. SCRATCH is a temporary buffer for debugging/chat
local BUFFER_STATE = {
  SCRATCH = nil,
  ORIGIN = nil,
}

local PROMPT_ARGS_STATE = {
  current_buffer_path = nil,
  current_buffer_context = nil,
  current_buffer_filetype = nil,
  visual_selection = nil,
  user_query = nil,
  replace = nil,
  context_files = nil,
}

local M = {}
local api = vim.api

M.NS_ID = api.nvim_create_namespace 'kznllm_ns'

M.TEMPLATE_DIRECTORY = vim.fn.stdpath 'data' .. '/lazy/kznllm/templates'

local group = api.nvim_create_augroup('LLM_AutoGroup', { clear = true })

---Handles visual selection depending on the specified mode and some expected states of the user's current buffer.
--- Returns an appropriate position to stream output tokens and
---
---@param mode string neovim mode returned by vim.api.nvim_get_mode().mode
---@param opts table optional values including debug mode
---@return integer stream_end_extmark_id this extmark determines where to stream output tokens
---@return string visual_selection returns the full selection
local function get_visual_selection(mode, opts)
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

  if not debug then
    api.nvim_buf_set_text(BUFFER_STATE.ORIGIN, srow, scol, erow, ecol, {})
  end

  return stream_end_extmark_id, visual_selection
end

---Renders a prompt template using minijinja-cli and returns the rendered lines
---
---@param prompt_template_path string an absolute path to a jinja file
---@param prompt_args table typically PROMPT_ARGS_STATE which needs to be json encoded
---@return string rendered_prompt
local function make_prompt_from_template(prompt_template_path, prompt_args)
  local json_data = vim.json.encode(prompt_args)
  local active_job = Job:new {
    command = 'minijinja-cli',
    args = { '-f', 'json', prompt_template_path, '-' },
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

  vim.ui.input({ prompt = 'prompt: ' }, function(input)
    if input ~= nil then
      BUFFER_STATE.ORIGIN = api.nvim_win_get_buf(0)
      local mode = api.nvim_get_mode().mode

      local stream_end_extmark_id, visual_selection = get_visual_selection(mode, opts)
      local replace_mode = not (mode == 'n')

      PROMPT_ARGS_STATE.user_query = input
      PROMPT_ARGS_STATE.visual_selection = visual_selection
      PROMPT_ARGS_STATE.replace = replace_mode

      -- don't update current context when in debug mode
      if BUFFER_STATE.SCRATCH == nil then
        -- similar to rendering a template, but we want to get the context of the file without relying on the changes being saved
        PROMPT_ARGS_STATE.current_buffer_path = api.nvim_buf_get_name(BUFFER_STATE.ORIGIN)
        PROMPT_ARGS_STATE.current_buffer_filetype = vim.bo.filetype
        PROMPT_ARGS_STATE.current_buffer_context = table.concat(api.nvim_buf_get_lines(BUFFER_STATE.ORIGIN, 0, -1, false), '\n')
      end

      -- project scoped context
      local context_dir_id, context_dir, context_files
      local home_directory = Path:new(vim.fn.expand '~')

      context_dir_id = opts and opts.context_dir_id or '.kzn'
      context_dir = Path:new(vim.fn.getcwd())

      while not (context_dir / context_dir_id):exists() and context_dir:is_dir() do
        if context_dir:absolute() == home_directory:absolute() then
          context_dir = nil
          break
        end
        context_dir = context_dir:parent()
      end

      if context_dir then
        context_dir = context_dir / context_dir_id
        context_files = Scan.scan_dir(context_dir:absolute(), { hidden = false })
        vim.print('using context at: ' .. context_dir:absolute())
      end

      PROMPT_ARGS_STATE.context_files = context_files

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

        table.insert(rendered_messages, { role = message.role, content = make_prompt_from_template(template_path:absolute(), PROMPT_ARGS_STATE) })

        if debug then
          write_content_at_extmark(message.role .. ':\n\n', stream_end_extmark_id)
          write_content_at_extmark(make_prompt_from_template(template_path:absolute(), PROMPT_ARGS_STATE), stream_end_extmark_id)
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
    end
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
