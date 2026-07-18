  @doc """
  Creates a record with a generated UUID v4 `:id`, an ISO 8601 `:uploaded_at`,
  and a `:pending` `:status`. Returns `{:ok, record}`.
  """
  @spec create(GenServer.server(), map()) :: {:ok, map()}
  def create(server, metadata), do: GenServer.call(server, {:create, metadata})