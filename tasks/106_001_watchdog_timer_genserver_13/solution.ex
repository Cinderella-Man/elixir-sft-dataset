  @doc """
  Stops monitoring `name`. After returning, no timeout callback fires for `name`.
  No-op for unknown names.
  """
  @spec unregister(term()) :: :ok
  def unregister(name) do
    GenServer.call(__MODULE__, {:unregister, name})
  end