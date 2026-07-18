  defp safe_to_term(bin) do
    {:ok, :erlang.binary_to_term(bin, [:safe])}
  rescue
    _ -> :error
  end