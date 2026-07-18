  @spec generate_version_id() :: String.t()
  defp generate_version_id do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end