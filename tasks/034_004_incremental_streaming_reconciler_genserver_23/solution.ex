  @doc """
  Feeds one record from the left stream.

  Returns `{:matched, entry}` if a pending right record with the same key existed,
  otherwise `:pending` (parking the record, replacing any pending-left record with the
  same key).
  """
  @spec push_left(GenServer.server(), stream_record()) :: {:matched, entry()} | :pending
  def push_left(server, record) when is_map(record) do
    GenServer.call(server, {:push, :left, record})
  end