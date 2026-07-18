  @doc """
  Fetches stored metadata by `id`, returning `{:ok, metadata}` or
  `{:error, :not_found}`.
  """
  @spec get(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(server, id), do: GenServer.call(server, {:get, id})