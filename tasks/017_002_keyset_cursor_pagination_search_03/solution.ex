  defp decode_cursor(params, field) do
    case Map.get(params, "cursor") do
      nil ->
        {:ok, nil}

      "" ->
        {:ok, nil}

      c when is_binary(c) ->
        with {:ok, bin} <- Base.url_decode64(c, padding: false),
             {:ok, {^field, value, id}} <- safe_to_term(bin) do
          {:ok, {value, id}}
        else
          _ -> {:error, :invalid_cursor}
        end

      _ ->
        {:error, :invalid_cursor}
    end
  end