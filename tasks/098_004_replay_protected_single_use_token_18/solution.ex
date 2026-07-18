  @doc """
  Issues a fresh single-use token for `payload`, valid for `ttl_seconds` seconds.

  `payload` may be any Elixir term; `ttl_seconds` must be a positive integer. The
  returned binary is URL-safe base64 without padding and encodes a fresh random
  nonce, the payload, the issue time, the expiry time and an HMAC-SHA256
  signature over all of them. Two calls never produce the same token, even for
  identical payloads, because each carries a distinct nonce.
  """
  @spec issue(GenServer.server(), term(), pos_integer()) :: token()
  def issue(server, payload, ttl_seconds)
      when is_integer(ttl_seconds) and ttl_seconds > 0 do
    GenServer.call(server, {:issue, payload, ttl_seconds})
  end