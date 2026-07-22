  defp build_rules(rules) do
    if Keyword.keyword?(rules) do
      Enum.reduce_while(rules, {:ok, %{}}, fn {field, rule}, {:ok, acc} ->
        if valid_rule?(rule) do
          {:cont, {:ok, Map.put(acc, field, rule)}}
        else
          {:halt, {:error, {:invalid_rule, field}}}
        end
      end)
    else
      {:error, :invalid_rules}
    end
  end