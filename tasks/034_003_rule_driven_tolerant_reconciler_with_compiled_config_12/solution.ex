  defp validate_rules(opts) do
    case Keyword.fetch(opts, :rules) do
      :error -> {:ok, %{}}
      {:ok, rules} when is_list(rules) -> build_rules(rules)
      {:ok, _other} -> {:error, :invalid_rules}
    end
  end