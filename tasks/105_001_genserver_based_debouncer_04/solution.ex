def call(key, delay_ms, func)
    when is_integer(delay_ms) and delay_ms >= 0 and is_function(func, 0) do
  GenServer.cast(__MODULE__, {:debounce, key, delay_ms, func})
end