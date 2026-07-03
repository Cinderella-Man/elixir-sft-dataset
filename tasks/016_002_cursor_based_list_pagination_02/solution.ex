  def paginate(items, params \\ %{}) when is_list(items) do
    limit = parse_limit(params)
    direction = parse_direction(params)
    cursor_id = parse_cursor(params)

    sorted = Enum.sort_by(items, & &1.id)

    window =
      case {direction, cursor_id} do
        {:next, nil} -> Enum.take(sorted, limit)
        {:next, c} -> sorted |> Enum.filter(&(&1.id > c)) |> Enum.take(limit)
        {:prev, nil} -> Enum.take(sorted, limit)
        {:prev, c} -> sorted |> Enum.filter(&(&1.id < c)) |> Enum.take(-limit)
      end

    build_result(sorted, window, limit)
  end