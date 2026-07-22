  # Extract the value of the `href` attribute from a raw attribute string.
  # Handles double-quoted, single-quoted, and unquoted values.
  defp extract_href(attrs_raw) do
    cond do
      m = Regex.run(~r/\bhref\s*=\s*"([^"]*)"/i, attrs_raw, capture: :all_but_first) ->
        hd(m)

      m = Regex.run(~r/\bhref\s*=\s*'([^']*)'/i, attrs_raw, capture: :all_but_first) ->
        hd(m)

      m = Regex.run(~r/\bhref\s*=\s*([^\s>]+)/i, attrs_raw, capture: :all_but_first) ->
        # Unquoted values may contain slashes (https://…). Only a trailing
        # "/" that is simultaneously the tag's own self-closing marker (the
        # very end of the attribute string) is not part of the value.
        value = hd(m)
        trimmed = String.trim_trailing(attrs_raw)

        if String.ends_with?(value, "/") and String.ends_with?(trimmed, value) do
          String.slice(value, 0..-2//1)
        else
          value
        end

      true ->
        nil
    end
  end