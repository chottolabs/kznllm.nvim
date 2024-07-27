local M = {}

local actions = require 'telescope.actions'
local action_state = require 'telescope.actions.state'
local pickers = require 'telescope.pickers'
local finders = require 'telescope.finders'
local conf = require('telescope.config').values

function M.find_files_custom_fd(opts, callback_fn)
  opts = opts or {}

  -- Check if fd is available
  if vim.fn.executable 'fd' ~= 1 then
    print "Error: 'fd' command not found. Please install fd-find."
    return
  end

  -- Prompt user for fd arguments
  local user_args = vim.fn.input 'Enter fd arguments (e.g., --type f): '

  -- Construct the fd command
  local fd_command = { 'fd', '-a' }
  for arg in user_args:gmatch '%S+' do
    table.insert(fd_command, arg)
  end

  pickers
    .new(opts, {
      prompt_title = 'Find Files (Custom fd)',
      finder = finders.new_oneshot_job(fd_command, {
        entry_maker = function(entry)
          return {
            value = entry,
            display = vim.fn.fnamemodify(entry, ':t'),
            ordinal = entry,
          }
        end,
      }),
      previewer = conf.file_previewer(opts),
      sorter = conf.file_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local picker = action_state.get_current_picker(prompt_bufnr)
          local selections = picker:get_multi_selection()
          actions.close(prompt_bufnr)
          local items = {}
          for _, selection in ipairs(selections) do
            table.insert(items, selection.value)
          end
          callback_fn(items)
        end)
        -- Override the default Tab behavior
        map('n', '<Tab>', function()
          local selection = action_state.get_selected_entry()
          if selection then
            actions.toggle_selection(prompt_bufnr)
          end
        end)
        return true
      end,
    })
    :find()
end

return M
