  @doc """
  Decrements the counter for `node_id` by `amount` (default `1`).

  `amount` must be a positive integer; raises `ArgumentError` otherwise.

  Returns `:ok`.
  """
  @spec decrement(server(), node_id(), amount()) :: :ok
  def decrement(server, node_id, amount \\ 1) do
    validate_amount!(amount, :decrement)
    GenServer.call(server, {:decrement, node_id, amount})
  end