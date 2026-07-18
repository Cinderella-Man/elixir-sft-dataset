  @doc """
  Adds a named override layer, or replaces an existing one in place, keeping its
  precedence position. Returns `:ok`.
  """
  @spec put_layer(GenServer.server(), term(), map()) :: :ok
  def put_layer(server, layer_name, config_map) when is_map(config_map) do
    GenServer.call(server, {:put_layer, layer_name, config_map})
  end