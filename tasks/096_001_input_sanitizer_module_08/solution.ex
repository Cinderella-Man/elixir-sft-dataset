  # Pull the leading tag name from a raw tag string.  Always lowercased.
  defp extract_tag_name(raw) do
    case Regex.run(~r/\A\s*([a-zA-Z][a-zA-Z0-9\-]*)/, raw, capture: :all_but_first) do
      [name] -> String.downcase(name)
      _ -> ""
    end
  end