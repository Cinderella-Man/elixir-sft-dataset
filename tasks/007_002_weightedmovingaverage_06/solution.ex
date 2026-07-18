  @doc "Pushes `value` into the weighted moving average for `name`. Returns `:ok`."
  @spec push(GenServer.server(), term(), number()) :: :ok
  def push(server, name, value) when is_number(value) do
    GenServer.call(server, {:push, name, value})
  end