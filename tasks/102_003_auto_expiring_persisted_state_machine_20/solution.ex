  @doc """
  Returns `{:ok, list}` where `list` is every recorded transition for
  `entity_id` in chronological (insertion) order.

  Each entry is a map with keys `:event`, `:from_state`, `:to_state`, and
  `:inserted_at`.
  """
  @spec history(GenServer.server(), String.t()) :: {:ok, [map()]}
  def history(server, entity_id) do
    GenServer.call(server, {:history, entity_id})
  end