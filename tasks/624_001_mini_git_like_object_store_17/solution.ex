  @doc """
  Retrieves previously-stored content by its SHA-1 hex digest.

  Returns `{:ok, content}` or `{:error, :not_found}`.
  """
  @spec retrieve(GenServer.server(), String.t()) :: {:ok, binary()} | {:error, :not_found}
  def retrieve(server, hash) when is_binary(hash) do
    GenServer.call(server, {:retrieve, hash})
  end