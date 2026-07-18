  @doc """
  Reserves `tokens` from the named bucket for up to `lease_timeout_ms`.

  Returns `{:ok, lease_id, remaining}` on success or
  `{:error, :empty, retry_after_ms}` when the bucket doesn't have enough
  free tokens.
  """
  @spec acquire_lease(
          GenServer.server(),
          term(),
          pos_integer(),
          number(),
          pos_integer(),
          pos_integer()
        ) ::
          {:ok, reference(), non_neg_integer()}
          | {:error, :empty, pos_integer()}
  def acquire_lease(server, bucket, capacity, refill_rate, tokens, lease_timeout_ms)
      when is_integer(capacity) and capacity > 0 and
             is_number(refill_rate) and refill_rate > 0 and
             is_integer(tokens) and tokens > 0 and tokens <= capacity and
             is_integer(lease_timeout_ms) and lease_timeout_ms > 0 do
    GenServer.call(
      server,
      {:acquire_lease, bucket, capacity, refill_rate * 1.0, tokens, lease_timeout_ms}
    )
  end