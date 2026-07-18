  @doc """
  Retrieves the content stored under `hash`, or `{:error, :not_found}`.
  """
  @spec retrieve(GenServer.server(), hash) :: {:ok, binary()} | {:error, :not_found}
  def retrieve(server, hash) when is_binary(hash) do
    GenServer.call(server, {:retrieve, hash})
  end