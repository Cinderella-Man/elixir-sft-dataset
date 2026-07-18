  @doc "Subscribes the calling process to notifications for `user_id`."
  @spec subscribe(server(), term()) :: :ok
  def subscribe(server \\ __MODULE__, user_id) do
    {:ok, _pid} = Registry.register(server, user_id, nil)
    :ok
  end