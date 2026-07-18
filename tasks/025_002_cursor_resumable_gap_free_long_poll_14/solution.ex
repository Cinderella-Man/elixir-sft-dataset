  @doc """
  Publishes `payload` to `user_id`, returning `{:ok, seq}` with the assigned
  sequence number.
  """
  @spec publish(server(), user_id(), payload()) :: {:ok, seq()}
  def publish(server \\ __MODULE__, user_id, payload) do
    GenServer.call(server, {:publish, user_id, payload})
  end