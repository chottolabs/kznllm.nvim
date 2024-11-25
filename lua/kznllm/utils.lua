local api = vim.api

local M = {}

M.OS_PATH_SEP = package.config:sub(1, 1)

function M.join_path(paths)
  return table.concat(paths, M.OS_PATH_SEP)
end

local function get_plugin_dir()
  -- Get the current file's path from debug info
  local source = debug.getinfo(1, 'S').source:sub(2)

  -- Split path into components
  local parts = {}
  for part in string.gmatch(source, '[^' .. M.OS_PATH_SEP .. ']+') do
    table.insert(parts, part)
  end

  -- Remove last 3 components to get plugin root
  for _ = 1, 3 do
    table.remove(parts)
  end

  return M.OS_PATH_SEP .. M.join_path(parts)
end

-- NOTE: this is a relative path meant to point at the template directory
M.PLUGIN_PATH = get_plugin_dir()
M.TEMPLATE_PATH = M.join_path({ M.PLUGIN_PATH, 'templates' })

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
  local _, srow, scol = unpack(vim.fn.getpos('v'))
  local _, erow, ecol = unpack(vim.fn.getpos('.'))

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

---project scoped context
---
---Retrieves project files based on the context directory identifier in the current working directory.
---
---@return { path: string, content: string }? context_files list of files in the context directory
function M.get_project_files()
  if vim.fn.executable('fd') ~= 1 then
    -- only use project mode if `fd` is available
    return
  end

  local fd_dir_result = vim.system({ 'fd', '-td', '-HI', '.kzn', '-1' }):wait()
  local context_dir = vim.trim(fd_dir_result.stdout)

  -- do not respect `.gitignore`, look for hidden
  local fd_files_result = vim.system({ 'fd', '-tf', '-L', '.', context_dir }):wait()
  local files = {}
  for file in vim.gsplit(fd_files_result.stdout, '\n', { plain = true, trimempty = true }) do
    local content = vim.fn.readfile(file)
    if #content > 0 then
      table.insert(files, { path = file, content = table.concat(content, '\n') })
    end
  end

  return files
end

---Creates a prompt from template
---@param opts { template_path: string, prompt_args: table }
---@return string
function M.make_prompt_from_template(opts)
  if vim.fn.executable('minijinja-cli') ~= 1 then
    error("Can't find minijinja-cli, download it from https://github.com/mitsuhiko/minijinja or add it to $PATH", 1)
  end

  local prompt_template_path = opts.template_path
  local json_data = vim.json.encode(opts.prompt_args)

  local active_job = vim
    .system(
      { 'minijinja-cli', '-f', 'json', '--lstrip-blocks', '--trim-blocks', prompt_template_path, '-' },
      { stdin = json_data }
    )
    :wait()

  if active_job.code ~= 0 then
    error('[minijinja-cli] (exit code: ' .. active_job.code .. ')\n' .. active_job.stderr, vim.log.levels.ERROR)
  end

  return active_job.stdout
end

return M
