local M = {}
local api = vim.api

--- Handle visual selection using the start of the visual selection and current
--- cursor position in the most common modes (i.e. visual, visual lines, visual block)
---
--- Note: visual block is handled the same as visual lines
--- @return string
local function get_visual_selection()
  -- use this instead of vim.api.nvim_buf_get_mark because it gives the "last" visual selection
  local _, srow, scol = unpack(vim.fn.getpos 'v')
  local _, erow, ecol = unpack(vim.fn.getpos '.')
  local mode = api.nvim_get_mode().mode

  -- Ensure start is before end
  if srow > erow or (srow == erow and scol > ecol) then
    srow, erow = erow, srow
    scol, ecol = ecol, scol
    -- move cursor to the other end of visual selection
    api.nvim_feedkeys('o', 'nx', false)
  end

  local lines = {}
  if mode == 'V' or mode == '\22' then
    lines = api.nvim_buf_get_lines(0, srow - 1, erow, false)
  elseif (srow == erow) and (scol == ecol) then
    lines = {}
  else
    lines = api.nvim_buf_get_text(0, srow - 1, scol - 1, erow - 1, ecol, {})
  end

  local content = table.concat(lines, '\n')

  if content == '' then
    vim.print 'no prompt selection found... use a [v]isual selection mode'
  end

  return content
end

local group = api.nvim_create_augroup('LLM_AutoGroup', { clear = true })

--- Invokes an LLM via a supported API spec
---
--- Must provide the function for constructing cURL arguments and a handler
--- function for processing server-sent events.
---
---@param opts { api_key_name: string, url: string, model: string, system_prompt: string, replace: boolean }
---@param make_job_fn function
function M.invoke_llm_and_stream_into_editor(opts, make_job_fn)
  api.nvim_clear_autocmds { group = group }

  local visual_selection = get_visual_selection()

  vim.ui.input({ prompt = 'prompt: ' }, function(input)
    if input == nil then
      return
    end

    if opts.replace then
      api.nvim_feedkeys('d', 'nx', false)
    else
      -- after getting lines, exit visual mode and go to end of the current line
      api.nvim_feedkeys(api.nvim_replace_termcodes('<Esc>', false, true, true), 'nx', false)
      api.nvim_feedkeys('$', 'nx', false)

      -- put new line, enter visual mode to highlight the completion
      api.nvim_put({ '' }, 'l', true, true)
    end

    local system_prompt = opts.system_prompt
    if system_prompt == nil then
      system_prompt = 'You are a tsundere uwu anime. Yell at me for not setting my configuration for my llm plugin correctly'
    end

    local user_prompt = table.concat({ visual_selection, input }, '\n')
    local active_job = make_job_fn(opts, system_prompt, user_prompt)
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

  api.nvim_set_keymap('n', '<Esc>', ':doautocmd User LLM_Escape<CR>', { noremap = true, silent = true })
end

return M
