  @doc "Runs `func`; returns its result or `{:error, :circuit_open}` (progressive recovery)."
  @spec call(GenServer.server(), (-> any())) :: any()
  def call(name, func) when is_function(func, 0) do
    GenServer.call(name, {:call, func})
  end