  defp validate_name(name) when is_binary(name) do
    if String.trim(name) == "" do
      {:error, :invalid_name}
    else
      {:ok, name}
    end
  end

  defp validate_name(_name), do: {:error, :invalid_name}