defp build_result(_sorted, [], limit) do
  %{
    data: [],
    meta: %{
      page_size: limit,
      next_cursor: nil,
      prev_cursor: nil,
      has_next: false,
      has_prev: false
    }
  }
end

defp build_result(sorted, window, limit) do
  first_id = hd(window).id
  last_id = List.last(window).id
  has_prev = Enum.any?(sorted, &(&1.id < first_id))
  has_next = Enum.any?(sorted, &(&1.id > last_id))

  %{
    data: window,
    meta: %{
      page_size: limit,
      next_cursor: if(has_next, do: encode_cursor(last_id), else: nil),
      prev_cursor: if(has_prev, do: encode_cursor(first_id), else: nil),
      has_next: has_next,
      has_prev: has_prev
    }
  }
end