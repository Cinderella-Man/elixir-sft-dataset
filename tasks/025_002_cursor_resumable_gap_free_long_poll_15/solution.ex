  @doc """
  Returns buffered `{seq, payload}` tuples for `user_id` with `seq > cursor`,
  oldest first.
  """
  @spec events_since(server(), user_id(), non_neg_integer()) :: [event()]
  def events_since(server \\ __MODULE__, user_id, cursor) do
    GenServer.call(server, {:events_since, user_id, cursor})
  end