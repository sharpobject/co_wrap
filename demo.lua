require"co_wrap"
get_main_thread = coroutine.call_from_main_thread(coroutine.running)
get_my_thread = coroutine.running
a = coroutine.create(function()
    local cos = {}
    local function print_some_numbers(n)
      for i=1,n do print("inner", i, coroutine.yield(i*i)) end
      print(get_main_thread())
      print(get_my_thread())
    end
    for i=1,3 do
      cos[i] = coroutine.create(print_some_numbers)
    end
    local n = 1
    while true do
      for i=1, #cos do
        if coroutine.status(cos[i]) ~= "dead" then
          print("outer", coroutine.resume(cos[i],n))
          n = n + 1
        end
      end
      print(coroutine.yield())
    end
  end)

for i=1,5 do print(coroutine.resume(a)) end
