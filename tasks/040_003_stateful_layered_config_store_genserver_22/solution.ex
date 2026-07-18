  @doc """
  Returns the deep-merged effective config: the base with every layer applied in
  order, later layers winning.
  """
  @spec get_config(GenServer.server()) :: map()
  def get_config(server), do: GenServer.call(server, :get_config)