local M = {}
local Job = require 'plenary.job'
local api = vim.api

--- Inserts content at the current cursor position in the active Neovim buffer.
---
--- This function schedules the insertion to occur on the next event loop iteration,
--- ensuring it doesn't interfere with other ongoing Neovim operations.
---
--- @param content string The text content to be inserted at the cursor position.
---
--- Behavior:
--- 1. Retrieves the current cursor position.
--- 2. Splits the input content into lines.
--- 3. Uses 'undojoin' to prevent creating an undo state for every token.
--- 4. Inserts the content at the cursor position.
--- 5. Moves the cursor to the end of the inserted content.
---
--- Note: This function modifies the current buffer and cursor position.
local function write_content_at_cursor(content)
  vim.schedule(function()
    local row, col = unpack(api.nvim_win_get_cursor(0))

    local lines = vim.split(content, '\n')

    -- avoid flooding undo history
    vim.cmd 'undojoin'
    api.nvim_put(lines, 'c', true, true)

    local num_lines = #lines
    local last_line_length = #lines[num_lines]
    api.nvim_win_set_cursor(0, { row + num_lines - 1, col + last_line_length })
  end)
end

--- Handle visual selection using the start of the visual selection and current
--- cursor position in the most common modes (i.e. visual, visual lines, visual block)
---
--- Note: visual block is handled the same as visual lines
--- @return string[]
local function get_visual_selection()
  -- use this instead of vim.api.nvim_buf_get_mark because it gives the "last" visual selection
  local _, srow, scol = unpack(vim.fn.getpos 'v')
  local _, erow, ecol = unpack(vim.fn.getpos '.')
  local mode = api.nvim_get_mode().mode

  -- Ensure start is before end
  if srow > erow or (srow == erow and scol > ecol) then
    srow, erow = erow, srow
    scol, ecol = ecol, scol
  end

  local lines = {}
  if mode == 'V' or mode == '\22' then
    lines = api.nvim_buf_get_lines(0, srow - 1, erow, false)
  elseif (srow == erow) and (scol == ecol) then
    lines = {}
  else
    lines = api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
  end
  return lines
end

--- Constructs a prompt string from an array of lines and resets the editor state.
---
--- This function takes an array of strings, concatenates them into a single string
--- with newline separators, and performs some editor state management actions.
---
--- @param lines string[] An array of strings to be concatenated into a prompt.
--- @return string
local function get_prompt(lines)
  local prompt = ''

  if lines then
    prompt = table.concat(lines, '\n')
    -- exit visual mode, go to end of the current line
    api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
    api.nvim_feedkeys('$', 'nx', false)
  end

  return prompt
end

local group = api.nvim_create_augroup('LLM_AutoGroup', { clear = true })
local active_job = nil

--- Invokes an LLM via a supported API spec
---
--- Must provide the function for constructing cURL arguments and a handler
--- function for processing server-sent events.
---
---@param opts { api_key_name: string, url: string, model: string, system_prompt: string, prompt: string }
---@param make_curl_args_fn function
---@param handle_data_fn function
function M.invoke_llm_and_stream_into_editor(opts, make_curl_args_fn, handle_data_fn)
  api.nvim_clear_autocmds { group = group }

  local visual_lines = get_visual_selection()
  local prompt = get_prompt(visual_lines)
  if prompt == '' then
    vim.print 'no prompt selection found... use a [v]isual selection mode'
    return
  end

  local system_prompt = opts.system_prompt or 'You are a tsundere uwu anime. Yell at me for not setting my configuration for my llm plugin correctly'
  local args = make_curl_args_fn(opts, prompt, system_prompt)

  -- put new line, enter visual mode to highlight the completion
  api.nvim_put({ '' }, 'l', true, true)
  api.nvim_feedkeys('v', 'nx', true)

  if active_job then
    active_job:shutdown()
    active_job = nil
  end

  active_job = Job:new {
    command = 'curl',
    args = args,
    on_stdout = function(_, out)
      local content = handle_data_fn(out)
      if content == '' then
        write_content_at_cursor(content)
      end
    end,
    on_stderr = function(_, _) end,
    on_exit = function()
      active_job = nil
    end,
  }

  active_job:start()

  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'LLM_Escape',
    callback = function()
      if active_job then
        active_job:shutdown()
        print 'LLM streaming cancelled'
        active_job = nil
      end
    end,
  })

  api.nvim_set_keymap('n', '<Esc>', ':doautocmd User LLM_Escape<CR>', { noremap = true, silent = true })
  return active_job
end

return M
