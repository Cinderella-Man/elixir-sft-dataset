  @doc """
  Lists every archived node (both `:direct` and `:cascade` origins), sorted by
  id ascending.
  """
  @spec list_archived(GenServer.server()) :: {:ok, [node_map()]}
  def list_archived(server) do
    GenServer.call(server, :list_archived)
  end