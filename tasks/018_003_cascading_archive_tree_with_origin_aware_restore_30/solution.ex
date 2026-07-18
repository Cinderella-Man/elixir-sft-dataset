  @doc """
  Archives a live node, cascading down its subtree when it is a folder.

  Returns `{:ok, %{node: node, cascaded: cascaded_ids}}` where `cascaded_ids`
  are the ids of the descendants archived by *this* call, sorted ascending.
  """
  @spec archive_node(GenServer.server(), id()) ::
          {:ok, %{node: node_map(), cascaded: [id()]}}
          | {:error, :not_found | :already_archived}
  def archive_node(server, id) do
    GenServer.call(server, {:archive_node, id})
  end