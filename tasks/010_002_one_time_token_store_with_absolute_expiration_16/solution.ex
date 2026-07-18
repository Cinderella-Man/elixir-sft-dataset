  @doc """
  Creates a new token containing `payload`.

  Returns `{:ok, token_id}`. The token expires at `now + ttl_ms` and is
  never extended — this is an absolute deadline.

  ## Options

    * `:ttl_ms` - override the default TTL for this specific token
  """
  @spec mint(server(), payload(), keyword()) :: {:ok, token_id()}
  def mint(server, payload, opts \\ []) do
    GenServer.call(server, {:mint, payload, opts})
  end