defp handle_line(trimmed, _handler_fn, processed, errors)
     when trimmed in ["", "[", "]"] do
  {processed, errors}
end

defp handle_line(trimmed, handler_fn, processed, errors) do
  payload = strip_trailing_comma(trimmed)

  case JSON.decode(payload) do
    {:ok, item} ->
      handler_fn.(item)
      {processed + 1, errors}

    {:error, _reason} ->
      {processed, errors + 1}
  end
end