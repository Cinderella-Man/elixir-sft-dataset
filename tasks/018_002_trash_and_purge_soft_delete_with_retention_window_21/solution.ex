  @doc """
  Creates a document from `attrs` (atom or string keys).

  Returns `{:ok, document}` or `{:error, errors}` when `title`/`content`
  are missing or blank.
  """
  @spec create_document(GenServer.server(), map()) :: {:ok, t()} | {:error, errors()}
  def create_document(server, attrs), do: GenServer.call(server, {:create, attrs})