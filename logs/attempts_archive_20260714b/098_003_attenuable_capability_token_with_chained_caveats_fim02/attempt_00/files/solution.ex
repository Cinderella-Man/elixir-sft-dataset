  def authorize(token, root_key, context)
      when is_binary(token) and is_binary(root_key) and is_map(context) do
    with {:ok, identifier, caveats, signature} <- decode(token) do
      expected = chain(root_key, identifier, caveats)

      if secure_compare(expected, signature) do
        check_caveats(caveats, context)
      else
        {:error, :invalid_signature}
      end
    end
  end

  def authorize(_token, _root_key, _context), do: {:error, :malformed}