  @spec generate_secret() :: secret()
  defp generate_secret do
    @secret_bytes
    |> :crypto.strong_rand_bytes()
    |> base32_encode()
  end