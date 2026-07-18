  @doc """
  Removes the layer named `layer_name`. Returns `:ok`.
  """
  @spec drop_layer(GenServer.server(), term()) :: :ok
  def drop_layer(server, layer_name) do
    GenServer.call(server, {:drop_layer, layer_name})
  end