  defp classify(line) do
    cond do
      caps = Regex.run(@heading_re, line, capture: :all_but_first) ->
        [hashes, title] = caps
        if String.length(hashes) == 2, do: {:heading, String.trim(title)}, else: :bad_heading

      caps = Regex.run(@item_re, line, capture: :all_but_first) ->
        {:item, build_item(caps)}

      Regex.match?(@bullet_re, line) ->
        :malformed_item

      true ->
        :ignore
    end
  end