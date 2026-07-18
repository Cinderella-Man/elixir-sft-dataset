  @doc """
  Stores `metadata`, adding an `:id` (UUID v4) and an `:uploaded_at` ISO 8601
  timestamp. Returns `{:ok, full_metadata}`.
  """
  def save(server, metadata), do: GenServer.call(server, {:save, metadata})