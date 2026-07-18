  defp ensure_unique(code_string, state) do
    if Map.has_key?(state.codes, code_string) do
      {:error, :already_exists}
    else
      :ok
    end
  end