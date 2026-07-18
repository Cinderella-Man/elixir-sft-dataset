  @doc "Runs `func` through the leaky-bucket breaker; result or `{:error, :circuit_open}`."
  @spec call(GenServer.server(), (-> any())) :: any()
  def call(name, func) when is_function(func, 0) do
    GenServer.call(name, {:call, func})
  end