  @doc """
  Generates a cryptographically random, base32-encoded secret.

  Produces 160 bits (20 bytes) of entropy via `:crypto.strong_rand_bytes/1`,
  encoded as an unpadded RFC 4648 base32 string of exactly 32 characters.
  """
  @spec generate_secret() :: String.t()
  def generate_secret do
    20
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end