  # Generates a URL-safe, base64-encoded, 16-byte random session ID (~22 chars).
  @spec generate_session_id() :: session_id()
  defp generate_session_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end