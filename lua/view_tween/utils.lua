local ffi = require("view_tween.ffi")

local uv = vim.loop
local api = vim.api

local HAS_NVIM_0_8 = vim.fn.has("nvim-0.8") == 1

local M = {}

---@class WinView
---@field lnum integer # Cursor line number
---@field col integer # Cursor column (0 indexed)
---@field coladd integer # Cursor column offset for 'virtualedit'
---@field curswant integer # Column for vertical movement
---@field leftcol integer # First column displayed
---@field skipcol integer # Columns skipped
---@field topfill integer # Filler lines (i.e. deleted lines in diff mode)
---@field topline integer # First line in the window

---@param value number
---@param min number
---@param max number
---@return number
function M.clamp(value, min, max)
  if value < min then return min end
  if value > max then return max end
  return value
end

---@param value number
---@return integer
function M.round(value)
  return math.floor(value + 0.5)
end

---Get the sign of a given number.
---@param n number
---@return -1|0|1
function M.sign(n)
  return (n > 0 and 1 or 0) - (n < 0 and 1 or 0)
end

---Get the current time (ms)
---@return number
function M.now()
  return uv.hrtime() / 1000000
end

function M.tbl_pack(...)
  return { n = select("#", ...), ... }
end

function M.tbl_unpack(t, i, j)
  return unpack(t, i or 1, j or t.n or #t)
end

---@param winid? integer
---@return WinView
function M.get_winview(winid)
  local ret

  api.nvim_win_call(winid or 0, function()
    ret = vim.fn.winsaveview()
  end)

  return ret
end

---@param view WinView
---@param winid? integer
function M.set_winview(view, winid)
  api.nvim_win_call(winid or 0, function()
    vim.fn.winrestview(view)
  end)
end

---Get effective window height.
---@param winid integer
---@return integer
function M.get_win_height(winid)
  local height = api.nvim_win_get_height(winid)

  if not HAS_NVIM_0_8 then
    return height
  end

  return height - (vim.wo[winid].winbar ~= "" and 1 or 0)
end

---@param winid? integer
function M.get_winline(winid)
  local ret

  api.nvim_win_call(winid or 0, function ()
    ret = vim.fn.winline()
  end)

  return ret
end

---@param winid integer
---@return integer
function M.get_scrolloff(winid)
  winid = winid or 0
  local height = M.get_win_height(winid)
  local so_opt = vim.wo[winid].scrolloff
  local so = M.clamp(so_opt, 0, math.floor(height / 2))

  if height % 2 == 0 and so_opt >= height / 2 then
    so = so - 1
  end

  return so
end

---Set the (1,0)-indexed cursor position without having to worry about
---out-of-bounds coordinates. The line number is clamped to the number of lines
---in the target buffer. Respects `curswant`.
---@param winid integer
---@param line? integer
---@param column? integer
function M.set_cursor(winid, line, column)
  local bufnr = api.nvim_win_get_buf(winid)
  line = M.clamp(line or 1, 1, api.nvim_buf_line_count(bufnr))
  ---@diagnostic disable-next-line: redundant-parameter
  local curswant = vim.fn.getcurpos(winid)[5] - 1
  column = math.max(0, column or curswant)

  pcall(api.nvim_win_set_cursor, winid, { line, column })
end

---@param winid integer
---@param line_from integer
---@param line_to integer
---@return integer delta
function M.get_scroll_delta(winid, line_from, line_to)
  local ret

  local bufnr = api.nvim_win_get_buf(winid)
  line_from = math.max(line_from, 1)
  line_to = math.min(line_to, api.nvim_buf_line_count(bufnr))
  local sign = M.sign(line_to - line_from)

  if sign == 0 then
    ret = 0
  else
    local cur = line_from
    local delta = 0
    local fold_edge

    while (line_to - cur) * sign > 0 do
      local fold_info = ffi.fold_info(winid, cur)

      if fold_info.start ~= 0 and fold_info.lines ~= 0 then
        if sign == -1 then
          fold_edge = fold_info.start
        else
          fold_edge = cur + fold_info.lines - 1
        end
        cur = fold_edge + sign
      else
        cur = cur + sign
      end

      delta = delta + sign
    end

    ret = delta
  end

  return ret
end

---@param winid integer
---@param line integer
---@param delta number
---@return integer target_line
function M.resolve_scroll_delta(winid, line, delta)
  delta = M.round(delta)
  local ret

  api.nvim_win_call(winid, function()
    local view = M.get_winview(winid)
    local bufnr = api.nvim_win_get_buf(winid)
    local sign = M.sign(delta)

    if sign == 0 then ret = line; return end

    local idelta = M.round(delta * sign)
    local fold_fn = sign == -1 and vim.fn.foldclosed or vim.fn.foldclosedend
    ret = line

    for _ = view.topline, idelta do
      local fold_edge = fold_fn(ret)
      if fold_edge then
        ret = fold_edge + sign
      else
        ret = ret + sign
      end
    end

    ret = M.clamp(ret, 1, api.nvim_buf_line_count(bufnr))
  end)

  return ret
end

return M
