  @doc """
  Returns `true` if an object file exists for `hash`, `false` otherwise.
  """
  @spec has_object?(server(), hash()) :: boolean()
  def has_object?(server, hash) do
    GenServer.call(server, {:has_object?, hash})
  end