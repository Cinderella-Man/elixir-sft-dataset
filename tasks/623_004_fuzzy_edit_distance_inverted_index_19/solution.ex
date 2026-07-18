  @doc """
  Index the document `id` with the given `text`.

  The text is tokenized and, per document, the number of occurrences of each surviving
  token is stored. Re-indexing an existing `id` cleanly replaces its previous version.
  """
  @spec index(GenServer.server(), String.t(), String.t()) :: :ok
  def index(server, id, text) do
    GenServer.call(server, {:index, id, text})
  end