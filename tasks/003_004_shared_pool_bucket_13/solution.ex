  @doc """
  Attempts to atomically drain `tokens` from both the per-key bucket and the
  shared global pool.

  Returns `{:ok, key_remaining, global_remaining}` on success, or
  `{:error, :key_empty | :global_empty, retry_after_ms}` on rejection.
  `:key_empty` takes precedence when both levels would fail.
  """
  @spec acquire(GenServer.server(), term(), pos_integer(), number(), pos_integer()) ::
          {:ok, non_neg_integer(), non_neg_integer()}
          | {:error, :key_empty | :global_empty, pos_integer()}
  def acquire(server, bucket_name, key_capacity, key_refill_rate, tokens \\ 1)
      when is_integer(key_capacity) and key_capacity > 0 and
             is_number(key_refill_rate) and key_refill_rate > 0 and
             is_integer(tokens) and tokens > 0 do
    GenServer.call(
      server,
      {:acquire, bucket_name, key_capacity, key_refill_rate * 1.0, tokens}
    )
  end