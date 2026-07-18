  defp generate_upload_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end