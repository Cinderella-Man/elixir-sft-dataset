          | {:error, :rate_limited, atom(), non_neg_integer()}
  def check(server, key, [_ | _] = tiers) do
    :ok = validate_tiers!(tiers)
    GenServer.call(server, {:check, key, tiers})
  end