  @doc "Publishes `payload` to every process currently subscribed to `user_id`."
  @spec publish(server(), term(), term()) :: :ok
  def publish(server \\ __MODULE__, user_id, payload) do
    Registry.dispatch(server, user_id, fn entries ->
      for {pid, _value} <- entries, do: send(pid, {:notification, payload})
    end)

    :ok
  end