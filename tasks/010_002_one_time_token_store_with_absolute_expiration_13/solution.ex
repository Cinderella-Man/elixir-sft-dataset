  @spec generate_token_id() :: token_id()
  defp generate_token_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end