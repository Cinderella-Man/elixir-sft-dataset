  @doc """
  Stores `metadata` under `hash`. Returns `{:ok, :created, record}` for a new hash
  (adding `:id`, `:uploaded_at`, `:upload_count` = 1) or `{:ok, :exists, record}`
  for a known hash (incrementing `:upload_count`, preserving original fields).
  """
  @spec save(GenServer.server(), String.t(), map()) :: {:ok, :created | :exists, map()}
  def save(server, hash, metadata), do: GenServer.call(server, {:save, hash, metadata})