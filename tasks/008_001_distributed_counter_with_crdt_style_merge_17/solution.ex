  @doc """
  Increments the counter for `node_id` by `amount` (default `1`).

  `amount` must be a positive integer; raises `ArgumentError` otherwise.

  Returns `:ok`.
  """
  @spec increment(server(), node_id(), amount()) :: :ok
  def increment(server, node_id, amount \\ 1) do
    validate_amount!(amount, :increment)
    GenServer.call(server, {:increment, node_id, amount})
  end