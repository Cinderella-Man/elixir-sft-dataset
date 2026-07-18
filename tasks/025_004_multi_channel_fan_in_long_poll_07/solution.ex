  @doc "Subscribes the calling process to notifications on `(user_id, channel)`."
  @spec subscribe(server(), term(), term()) :: :ok
  def subscribe(server \\ __MODULE__, user_id, channel) do
    {:ok, _pid} = Registry.register(server, {user_id, channel}, nil)
    :ok
  end