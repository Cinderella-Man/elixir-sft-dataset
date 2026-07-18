  @doc """
  Returns the list of layer names in precedence order (lowest precedence first).
  """
  @spec layers(GenServer.server()) :: [term()]
  def layers(server), do: GenServer.call(server, :layers)