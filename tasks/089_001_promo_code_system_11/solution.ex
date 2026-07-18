  defp fetch_code(code_string, state) do
    case Map.fetch(state.codes, code_string) do
      {:ok, code} -> {:ok, code}
      :error -> {:error, :not_found}
    end
  end