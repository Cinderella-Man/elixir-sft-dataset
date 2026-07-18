  @doc """
  Feeds one record from the right stream.

  Symmetric to `push_left/2`.
  """
  @spec push_right(GenServer.server(), stream_record()) :: {:matched, entry()} | :pending
  def push_right(server, record) when is_map(record) do
    GenServer.call(server, {:push, :right, record})
  end