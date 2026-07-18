  @doc "Manually resets the breaker to closed with zero failures."
  @spec reset(name()) :: :ok
  def reset(name) do
    GenServer.call(name, :reset)
  end