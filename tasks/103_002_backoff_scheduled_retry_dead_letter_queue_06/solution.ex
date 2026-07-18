  @doc "Pushes a failed `message` with backoff-scheduled retry. Returns `{:ok, id}`."
  @spec push(GenServer.server(), term(), term(), term(), map()) :: {:ok, term()}
  def push(server, queue_name, message, error_reason, metadata) when is_map(metadata) do
    GenServer.call(server, {:push, queue_name, message, error_reason, metadata})
  end