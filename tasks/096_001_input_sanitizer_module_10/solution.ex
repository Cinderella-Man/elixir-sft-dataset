  # Returns true when an href value is a javascript: URI.
  # Per the HTML spec, leading ASCII whitespace/control chars are stripped
  # before the scheme comparison.
  defp javascript_href?(value) do
    value
    |> String.replace(~r/[\x00-\x20]/, "")
    |> String.downcase()
    |> String.starts_with?("javascript:")
  end