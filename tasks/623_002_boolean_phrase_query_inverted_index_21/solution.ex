  @doc """
  Indexes `fields` (a map of field name to text) under `id`.

  Re-indexing an existing `id` cleanly replaces its previous version.
  """
  @spec index(GenServer.server(), String.t(), map()) :: :ok
  def index(server, id, fields) do
    GenServer.call(server, {:index, id, fields})
  end