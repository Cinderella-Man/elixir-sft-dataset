  # A token is expired when the current wall-clock time has reached or
  # passed `expires_at`. Strict `<` means that at exactly the TTL
  # boundary (now == issued_at + ttl) the token is already expired.
  defp check_expiry(expires_at, opts) do
    if now(opts) < expires_at do
      :ok
    else
      {:error, :expired}
    end
  end