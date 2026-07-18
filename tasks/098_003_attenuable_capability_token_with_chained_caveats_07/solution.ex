  def inspect_token(token) when is_binary(token) do
    with {:ok, identifier, caveats, _signature} <- decode(token) do
      {:ok, %{identifier: identifier, caveats: caveats}}
    end
  end

  def inspect_token(_token), do: {:error, :malformed}