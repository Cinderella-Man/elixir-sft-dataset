  @doc """
  Record a failed `message` under `queue_name`.

  Returns `{:ok, message_id}` where `message_id` is unique within the server.
  """
  @spec push(GenServer.server(), term(), term(), term(), map()) :: {:ok, term()}
  def push(server, queue_name, message, error_reason, metadata)
      when is_map(metadata) do
    GenServer.call(server, {:push, queue_name, message, error_reason, metadata})
  end