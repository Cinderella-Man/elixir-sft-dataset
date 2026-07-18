  @doc """
  Generates a cryptographically random, base32-encoded 160-bit secret
  (20 bytes → 32 characters, no padding).
  """
  @spec generate_secret() :: String.t()
  def generate_secret do
    @secret_bytes
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end