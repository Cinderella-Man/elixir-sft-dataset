  @spec walk_list(t(), list()) :: {list(), report()}
  defp walk_list(redactor, list) do
    {acc, rep} =
      Enum.reduce(list, {[], @empty_report}, fn el, {acc, rep} ->
        {new_el, new_rep} = walk(redactor, el)
        {[new_el | acc], merge(rep, new_rep)}
      end)

    {Enum.reverse(acc), rep}
  end