  @spec walk_any_list(t(), list()) :: {list(), report()}
  defp walk_any_list(redactor, list) do
    if Keyword.keyword?(list) and list != [] do
      walk_keyword(redactor, list)
    else
      walk_list(redactor, list)
    end
  end