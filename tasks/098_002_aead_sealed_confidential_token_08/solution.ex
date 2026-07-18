  @spec deserialize(binary()) :: {:ok, term()} | {:error, :malformed}
  defp deserialize(plaintext) do
    {:ok, :erlang.binary_to_term(plaintext, [:safe])}
  rescue
    ArgumentError -> {:error, :malformed}
  end