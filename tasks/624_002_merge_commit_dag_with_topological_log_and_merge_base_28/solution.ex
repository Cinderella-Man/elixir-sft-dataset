  @doc """
  Retrieves the content stored under `hash`.

  Returns `{:ok, content}` if present, otherwise `{:error, :not_found}`.
  """
  @spec retrieve(server(), hash()) :: {:ok, binary()} | {:error, :not_found}
  def retrieve(server, hash) when is_binary(hash) do
    GenServer.call(server, {:retrieve, hash})
  end