def publish(server \\ __MODULE__, user_id, channel, payload) do
  Registry.dispatch(server, {user_id, channel}, fn entries ->
    for {pid, _value} <- entries, do: send(pid, {:notification, channel, payload})
  end)

  :ok
end