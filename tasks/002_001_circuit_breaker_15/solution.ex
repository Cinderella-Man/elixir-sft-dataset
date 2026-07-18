  @doc """
  Execute `func` (a zero-arity function) through the circuit breaker.

  Returns `{:ok, result}` on success or `{:error, reason}` on failure /
  when the circuit is open.
  """
  @spec call(name(), (-> any())) :: {:ok, any()} | {:error, any()}
  def call(name, func) when is_function(func, 0) do
    GenServer.call(name, {:call, func})
  end