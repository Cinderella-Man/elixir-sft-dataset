defp execute(func) do
  try do
    case func.() do
      {:ok, _} = ok ->
        {ok, true}

      {:error, _} = error ->
        {error, false}

      other ->
        {{:error, {:unexpected_return, other}}, false}
    end
  rescue
    exception ->
      {{:error, exception}, false}
  end
end
