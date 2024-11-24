-- Buffer management singleton
local BufferManager = {}
local api = vim.api

local group = api.nvim_create_augroup('LLM_AutoGroup', { clear = true })

BufferManager.state = {
  buffers = {}, -- Map of buffer_id -> buffer state
  ns_id = api.nvim_create_namespace('kznllm_ns'),
}

---@class BufferState
---@field extmark_id integer?
---@field filetype string
---@field path string

---Initialize or get buffer state
---@param buf_id integer
---@return BufferState
function BufferManager:get_or_add_buffer(buf_id)
  if not self.state.buffers[buf_id] then
    self.state.buffers[buf_id] = {
      extmark_id = nil,
      filetype = vim.bo[buf_id].filetype,
      path = api.nvim_buf_get_name(buf_id),
    }

    -- Clean up state when buffer is deleted
    api.nvim_buf_attach(buf_id, false, {
      on_detach = function()
        self.state.buffers[buf_id] = nil
      end,
    })
  end
  return self.state.buffers[buf_id]
end

---Creates a scratch buffer with markdown highlighting
---@return integer buf_id
function BufferManager:create_scratch_buffer()
  local buf_id = api.nvim_create_buf(false, true)
  _ = self:get_or_add_buffer(buf_id)

  api.nvim_set_option_value('filetype', 'markdown', { buf = buf_id })
  api.nvim_set_option_value('swapfile', false, { buf = buf_id })

  api.nvim_set_current_buf(buf_id)
  api.nvim_set_option_value('wrap', true, { win = 0 })
  api.nvim_set_option_value('linebreak', true, { win = 0 })
  api.nvim_set_option_value('breakindent', true, { win = 0 })

  return buf_id
end

---Get buffer context without saving
---@param buf_id integer Buffer ID to get context from
---@return { filetype: string, path: string, text: string }
function BufferManager:get_buffer_context(buf_id)
  local state = self:get_or_add_buffer(buf_id)
  return {
    filetype = state.filetype,
    path = state.path,
    text = table.concat(api.nvim_buf_get_lines(buf_id, 0, -1, false), '\n'),
  }
end

---Write content at current buffer's extmark position. If extmark does not exist, set it to the current cursor position
---@param content string Content to write
---@param buf_id? integer Optional buffer ID, defaults to current
function BufferManager:write_content(content, buf_id)
  buf_id = buf_id or api.nvim_get_current_buf()
  local state = self:get_or_add_buffer(buf_id)

  if not state.extmark_id then
    -- Create new extmark at current cursor position
    local pos = api.nvim_win_get_cursor(0)
    state.extmark_id = api.nvim_buf_set_extmark(buf_id, self.state.ns_id, pos[1] - 1, pos[2], {})
  end

  local extmark = api.nvim_buf_get_extmark_by_id(buf_id, self.state.ns_id, state.extmark_id, { details = false })
  local mrow, mcol = extmark[1], extmark[2]
  local lines = vim.split(content, '\n')

  vim.cmd('undojoin')
  api.nvim_buf_set_text(buf_id, mrow, mcol, mrow, mcol, lines)
end

--- Makes a no-op change to the buffer
--- This is used before making changes to avoid calling undojoin after undo.
local function noop()
  api.nvim_buf_set_text(0, 0, 0, 0, 0, {})
end

---@param args table
function BufferManager:create_streaming_job(args, handle_sse_stream_fn, progress_fn, on_complete_fn)
  local buf_id = api.nvim_get_current_buf()
  local state = self:get_or_add_buffer(buf_id)

  --- should be safe to do this before any jobs
  noop()

  local captured_stdout = ''
  --- NOTE: vim.system can flush multiple consecutive lines into the same stdout buffer
  --- (different from how plenary jobs handles it)
  local job = vim.system(vim.list_extend({ 'curl' }, args), {
    stdout = function(err, data)
      if data == nil then
        return
      end
      progress_fn()
      captured_stdout = data
      local content = handle_sse_stream_fn(data)
      if content then
        vim.schedule(function()
          self:write_content(content, buf_id)
        end)
      end
    end,
  }, function(obj)
    on_complete_fn()
    vim.schedule(function()
      if obj.code and obj.code ~= 0 then
        vim.notify(('[curl] (exit code: %d) %s'):format(obj.code, captured_stdout), vim.log.levels.ERROR)
      else
        -- Clean up extmark on successful completion
        if state.extmark_id then
          api.nvim_buf_del_extmark(buf_id, self.state.ns_id, state.extmark_id)
          state.extmark_id = nil
        end
      end
    end)
  end)

  api.nvim_create_autocmd('User', {
    group = group,
    pattern = 'LLM_Escape',
    callback = function()
      if job:is_closing() ~= true then
        job:kill(9)
        print('LLM streaming cancelled')
      end
    end,
  })
  return job
end

-- Export the singleton
local M = {}
M.buffer_manager = BufferManager
return M
