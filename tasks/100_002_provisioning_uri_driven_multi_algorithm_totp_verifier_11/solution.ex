  @spec parse_secret(map()) :: {:ok, String.t()} | {:error, :missing_secret | :invalid_secret}
  defp parse_secret(params) do
    case Map.fetch(params, "secret") do
      :error ->
        {:error, :missing_secret}

      {:ok, raw} ->
        normalized =
          raw
          |> String.replace(~r/[\s=]/u, "")
          |> String.upcase()

        cond do
          normalized == "" -> {:error, :invalid_secret}
          base32?(normalized) -> {:ok, normalized}
          true -> {:error, :invalid_secret}
        end
    end
  end