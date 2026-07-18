  @doc """
  Creates a document with a non-empty `title` and `content`.

  Returns `{:ok, document}` with `lock_version: 0`, or `{:error, errors}`.
  """
  @spec create_document(server(), attrs()) :: {:ok, document()} | {:error, errors()}
  def create_document(s, attrs), do: GenServer.call(s, {:create, attrs})