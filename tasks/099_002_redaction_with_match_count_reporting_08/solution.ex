  @spec walk(t(), term()) :: {term(), report()}
  defp walk(redactor, data) do
    cond do
      is_struct(data) -> {data, @empty_report}
      is_map(data) -> walk_map(redactor, data)
      is_list(data) -> walk_any_list(redactor, data)
      is_binary(data) -> scrub_string(data)
      true -> {data, @empty_report}
    end
  end