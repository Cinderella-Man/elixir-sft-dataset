  @doc """
  Decodes, validates and consumes `token`.

  Returns `{:ok, payload}` the first time a valid, unexpired, not-yet-consumed
  token is redeemed, marking its nonce consumed. Subsequent redemptions of the
  same token return `{:error, :replayed}`.

  Failure reasons:

    * `{:error, :malformed}` — the token cannot be decoded at all (bad base64,
      too short to hold a MAC, header inconsistent with the remaining bytes,
      non-binary input, …).
    * `{:error, :invalid_signature}` — the structure parses but the HMAC computed
      with this server's secret does not match.
    * `{:error, :replayed}` — the nonce has already been consumed.
    * `{:error, :expired}` — the signature is valid and the nonce is unconsumed,
      but the current time is at or past `expires_at`.

  No failure path consumes anything.
  """
  @spec redeem(GenServer.server(), term()) :: {:ok, term()} | {:error, error()}
  def redeem(server, token) do
    GenServer.call(server, {:redeem, token})
  end