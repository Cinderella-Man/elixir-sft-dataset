  @spec index(GenServer.server(), term(), map(), keyword()) :: :ok
  @doc "Index a document. Re-indexing the same `id` replaces the previous version."
  def index(server, id, fields, opts \\ []) do
    GenServer.call(server, {:index, id, fields, opts})
  end