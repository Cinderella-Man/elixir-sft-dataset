  def execute(server, key, func, opts \\ []) when is_function(func, 0) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    base_delay_ms = Keyword.get(opts, :base_delay_ms, 100)
    max_delay_ms = Keyword.get(opts, :max_delay_ms, 5_000)

    retry_config = %{
      max_retries: max_retries,
      base_delay_ms: base_delay_ms,
      max_delay_ms: max_delay_ms
    }

    GenServer.call(server, {:execute, key, func, retry_config}, :infinity)
  end