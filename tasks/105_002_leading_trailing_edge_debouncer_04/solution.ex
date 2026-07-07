def call(key, delay_ms, func, opts \\ [])
    when is_integer(delay_ms) and delay_ms >= 0 and is_function(func, 0) and is_list(opts) do
  edge = Keyword.get(opts, :edge, :trailing)

  unless edge in @valid_edges do
    raise ArgumentError,
          "invalid :edge #{inspect(edge)}, expected one of #{inspect(@valid_edges)}"
  end

  GenServer.cast(__MODULE__, {:debounce, key, delay_ms, func, edge})
end