  defp encode_cursor(p, params) do
    {value, id} = key_of(p, params)

    {sort_field(params), value, id}
    |> :erlang.term_to_binary()
    |> Base.url_encode64(padding: false)
  end