  defp process_tag(raw, allow, pa) do
    trimmed = String.trim(raw)

    cond do
      # HTML comment, doctype, or processing instruction — discard
      String.starts_with?(trimmed, "!") or String.starts_with?(trimmed, "?") ->
        {"", pa}

      # Closing tag
      String.starts_with?(trimmed, "/") ->
        tag_name =
          trimmed
          |> String.slice(1..-1//1)
          |> extract_tag_name()

        cond do
          tag_name == "a" and pa ->
            # Consume the closing </a> of a poisoned anchor; reset state
            {"", false}

          tag_name in allow ->
            {"</#{tag_name}>", pa}

          true ->
            {"", pa}
        end

      # Opening (or self-closing) tag
      true ->
        tag_name = extract_tag_name(trimmed)
        attrs_raw = String.slice(trimmed, String.length(tag_name)..-1//1)
        self_closing? = attrs_raw |> String.trim_trailing() |> String.ends_with?("/")

        if tag_name in allow do
          rebuild_tag(tag_name, attrs_raw, self_closing?, pa)
        else
          {"", pa}
        end
    end
  end