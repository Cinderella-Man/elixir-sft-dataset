  @doc """
  Appends `caveat` to `token` without needing the root key.

  Returns `{:ok, new_token}` whose caveats are the old ones, in order, followed
  by `caveat`. Returns `{:error, :malformed}` if `token` is not decodable, if
  either argument is not a binary, or if `caveat` is empty or longer than
  #{@max_caveat_size} bytes. The original token is untouched.
  """
  @spec attenuate(token(), caveat()) :: {:ok, token()} | {:error, :malformed}
  def attenuate(token, caveat)
      when is_binary(token) and is_binary(caveat) and byte_size(caveat) in 1..@max_caveat_size do
    with {:ok, identifier, caveats, signature} <- decode(token) do
      new_signature = :crypto.mac(:hmac, :sha256, signature, caveat)
      {:ok, encode(identifier, caveats ++ [caveat], new_signature)}
    end
  end

  def attenuate(_token, _caveat), do: {:error, :malformed}