  defp encode_key(key) do
    key
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end