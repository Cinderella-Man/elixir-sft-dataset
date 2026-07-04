  defp classify(line) do
    cond do
      caps = Regex.run(@heading_re, line, capture: :all_but_first) ->
        [hashes, title] = caps
        level = String.length(hashes)
        if level <= 6, do: {:heading, level, String.trim(title)}, else: :ignore

      caps = Regex.run(@item_re, line, capture: :all_but_first) ->
        {:item, build_item(caps)}

      true ->
        :ignore
    end
  end