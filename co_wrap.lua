local select = select
local table_insert = table.insert
local table_remove = table.remove
-- utility to save multiple returns or varargs for later use
local NIL = {}
local function drop_one(x, ...)
  return ...
end
local save_exprs
save_exprs = function(return_first_x, ...)
  if return_first_x == 0 then
    local ret = {}
    for i=1,select("#", ...) do
      local item = select(i, ...)
      if item == nil then
        item = NIL
      end
      ret[i] = item
    end
    return ret
  end
  return select(1, ...), save_exprs(return_first_x-1, drop_one(...))
end
local unsave_exprs
unsave_exprs = function(t, idx, len)
  if not idx then
    idx = 0
    len = #t
  end
  if idx == len then
    return
  end
  idx = idx + 1
  local ret = t[idx]
  if ret == NIL then
    ret = nil
  end
  return ret, unsave_exprs(t, idx, len)
end

local co_stack = {}
local co_running = {}
local n_cos = 0
local real_yield = coroutine.yield
local real_resume = coroutine.resume
local real_status = coroutine.status
local real_create = coroutine.create
function coroutine.resume(co, ...)
  -- can't have the same coroutine running twice in our fake stack of coroutines 
  if co_running[co] then
    return false, "cannot resume non-suspended coroutine"
  end
  -- if we are called from the main thread, resume and trampoline
  if n_cos == 0 then
    n_cos = n_cos + 1
    co_stack[n_cos] = co
    co_running[co] = true
    local ok, op
    local stuff = save_exprs(0, co, ...)
    while true do
      local prev_co = stuff[1]
      ok, op, stuff = save_exprs(2, real_resume(unsave_exprs(stuff)))
      if ok and op == "resume" then
        -- trampoline and pass stuff to nested co
        n_cos = n_cos + 1
        co_stack[n_cos] = stuff[1]
        co_running[stuff[1]] = true
      elseif ok and (op == "yield" or op == "die") then
        -- coroutine yielded or died
        -- trampoline and pass stuff to parent co
        co_running[prev_co] = nil
        co_stack[n_cos] = nil
        n_cos = n_cos - 1
        if n_cos == 0 then
          -- parent co is topmost lua thread, so return
          return true, unsave_exprs(stuff)
        else
          table_insert(stuff, 1, true)
          table_insert(stuff, 1, co_stack[n_cos])
        end
      elseif ok and op == "call" then
        -- coroutine wants to call some function from the main thread
        -- get the results and pass them back to same co
        local func = table_remove(stuff, 1)
        stuff = save_exprs(0, func(unsave_exprs(stuff)))
        table_insert(stuff, 1, co_stack[n_cos])
      elseif not ok then
        -- coroutine errored
        -- trampoline and pass stuff to parent co
        co_running[prev_co] = nil
        co_stack[n_cos] = nil
        n_cos = n_cos - 1
        if n_cos == 0 then
          -- parent co is topmost lua thread, so return
          return false, op, unsave_exprs(stuff)
        else
          table_insert(stuff, 1, op)
          table_insert(stuff, 1, false)
          table_insert(stuff, 1, co_stack[n_cos])
        end
      else
        error("Fake coroutine lib: Not sure what happened")
      end
    end
  else
    -- tell the loop on the main thread that I'd like to resume pls
    return real_yield("resume", co, ...)
  end
end

function coroutine.yield(...)
  -- tell the loop on the main thread that I'd like to yield pls
  return real_yield("yield", ...)
end

function coroutine.status(co)
  if co_running[co] then
    return "running"
  else
    return real_status(co)
  end
end

function coroutine.create(f)
  return real_create(function(...)
    -- tell the loop on the main thread that I'd like to die pls
    return "die", f(...)
  end)
end

function coroutine.call_from_main_thread(f)
  return function(...)
    if n_cos == 0 then
      return f(...)
    else
      -- tell the loop on the main thread that I'd like to call pls
      return real_yield("call", f, ...)
    end
  end
end

--TODO: also reimplement coroutine.wrap

--coroutine.running should work fine as is.
