local co_stack = {}
local co_running = {}
local n_cos = 0
local real_yield = coroutine.yield
local real_resume = coroutine.resume
local real_status = coroutine.status
local real_create = coroutine.create

local co_wrap_resume
local co_wrap_loop
local co_wrap_loop_no_err
local co_wrap_run
local co_wrap_apply
local co_wrap_run

function co_wrap_apply(f, ...)
  return f(...)
end

function co_wrap_loop_no_err(op, ...)
  if op == "resume" then
    -- trampoline and pass stuff to nested co
    return co_wrap_resume(...)
  elseif op == "yield" then
    -- coroutine yielded or died
    -- trampoline and pass stuff to parent co
    co_running[co_stack[n_cos]] = nil
    co_stack[n_cos] = nil
    n_cos = n_cos - 1
    if n_cos == 0 then
      -- parent co is topmost lua thread, so return
      return true, ...
    end
    return co_wrap_run(co_stack[n_cos], true, ...)
  elseif op == "call" then
    return co_wrap_run(co_stack[n_cos], co_wrap_apply(...))
  else
    error("Fake coroutine lib: Not sure what happened")
  end
end

function co_wrap_loop(ok, ...)
  if not ok then
    -- coroutine errored
    -- trampoline and pass stuff to parent co
    co_running[co_stack[n_cos]] = nil
    co_stack[n_cos] = nil
    n_cos = n_cos - 1
    if n_cos == 0 then
      -- parent co is topmost lua thread, so return
      return ok, ...
    end
    return co_wrap_run(co_stack[n_cos], ok, ...)
  end
  return co_wrap_loop_no_err(...)
end

function co_wrap_resume(co, ...)
  n_cos = n_cos + 1
  co_stack[n_cos] = co
  co_running[co] = true
  return co_wrap_run(co, ...)
end

function co_wrap_run(...)
  return co_wrap_loop(real_resume(...))
end

function coroutine.resume(co, ...)
  -- can't have the same coroutine running twice in our fake stack of coroutines 
  if co_running[co] then
    return false, "cannot resume non-suspended coroutine"
  -- if we are called from the main thread, resume and trampoline
  elseif n_cos == 0 then
    return co_wrap_resume(co, ...)
  end
  -- tell the loop on the main thread that I'd like to resume pls
  return real_yield("resume", co, ...)
end

function coroutine.yield(...)
  -- tell the loop on the main thread that I'd like to yield pls
  return real_yield("yield", ...)
end

function coroutine.status(co)
  if co_running[co] then
    return "running"
  end
  return real_status(co)
end

function coroutine.create(f)
  return real_create(function(...)
    -- tell the loop on the main thread that I'd like to die pls
    return "yield", f(...)
  end)
end

function coroutine.call_from_main_thread(f)
  return function(...)
    if n_cos == 0 then
      return f(...)
    end
      -- tell the loop on the main thread that I'd like to call pls
    return real_yield("call", f, ...)
  end
end

coroutine.suspend = coroutine.call_from_main_thread(real_yield)

--TODO: also reimplement coroutine.wrap

--coroutine.running should work fine as is.
