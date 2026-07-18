  defp check_max_uses(%{max_uses: nil}, _code_string, _state), do: :ok

  defp check_max_uses(%{max_uses: max}, code_string, state) do
    if total_uses(state, code_string) >= max do
      {:error, :max_uses_exceeded}
    else
      :ok
    end
  end