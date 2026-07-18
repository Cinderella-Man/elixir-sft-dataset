  @doc """
  Return up to `count` messages held for `queue_name`, oldest-first, without
  removing them. Unknown or empty queues return `[]`.
  """
  @spec peek(GenServer.server(), term(), non_neg_integer()) :: [map()]
  def peek(server, queue_name, count)
      when is_integer(count) and count >= 0 do
    GenServer.call(server, {:peek, queue_name, count})
  end