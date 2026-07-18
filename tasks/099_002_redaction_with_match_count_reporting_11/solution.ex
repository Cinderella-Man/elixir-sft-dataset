  @spec walk_keyword(t(), keyword()) :: {keyword(), report()}
  defp walk_keyword(redactor, kw) do
    {acc, rep} =
      Enum.reduce(kw, {[], @empty_report}, fn {k, v}, {acc, rep} ->
        {new_v, new_rep} = redact_pair(redactor, k, v)
        {[{k, new_v} | acc], merge(rep, new_rep)}
      end)

    {Enum.reverse(acc), rep}
  end