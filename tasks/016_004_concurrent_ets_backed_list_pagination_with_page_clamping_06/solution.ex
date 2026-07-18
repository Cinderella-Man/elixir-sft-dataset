  @doc """
  Insert `item` (a map with at least an integer `:id`) under its id. A later
  insert with the same id overwrites the earlier one. Returns `:ok`.
  """
  @spec insert(:ets.tid(), map()) :: :ok
  def insert(table, %{id: id} = item) do
    :ets.insert(table, {id, item})
    :ok
  end