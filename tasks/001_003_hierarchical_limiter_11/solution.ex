  @doc """
  Checks whether a request for `key` passes every tier in `tiers`.

  `tiers` is a list of `{tier_name, max_requests, window_ms}` tuples.  A
  request is accepted only when every tier has capacity.  On success, returns
  `{:ok, remaining_by_tier}` — a map from tier name to the remaining
  allowance under that tier after accepting the request.

  On failure, returns `{:error, :rate_limited, tier_name, retry_after_ms}`
  identifying the tier that kept the request out for the longest and the wait
  (in milliseconds) until that tier would admit a new request.
  """
  @spec check(GenServer.server(), term(), [{atom(), pos_integer(), pos_integer()}, ...]) ::
          {:ok, %{atom() => non_neg_integer()}}
          | {:error, :rate_limited, atom(), non_neg_integer()}
  def check(server, key, [_ | _] = tiers) do
    :ok = validate_tiers!(tiers)
    GenServer.call(server, {:check, key, tiers})
  end