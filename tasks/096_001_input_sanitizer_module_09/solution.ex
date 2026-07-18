  # Extract the value of the `href` attribute from a raw attribute string.
  # Handles double-quoted, single-quoted, and unquoted values.
  defp extract_href(attrs_raw) do
    cond do
      m = Regex.run(~r/\bhref\s*=\s*"([^"]*)"/i, attrs_raw, capture: :all_but_first) ->
        hd(m)

      m = Regex.run(~r/\bhref\s*=\s*'([^']*)'/i, attrs_raw, capture: :all_but_first) ->
        hd(m)

      m = Regex.run(~r/\bhref\s*=\s*([^\s>\/]+)/i, attrs_raw, capture: :all_but_first) ->
        hd(m)

      true ->
        nil
    end
  end