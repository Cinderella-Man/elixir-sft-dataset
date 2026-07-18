  @doc """
  Subscribes the calling process to notifications for `user_id`.
  """
  @spec subscribe(server(), user_id()) :: :ok
  def subscribe(server \\ __MODULE__, user_id) do
    GenServer.call(server, {:subscribe, user_id, self()})
  end