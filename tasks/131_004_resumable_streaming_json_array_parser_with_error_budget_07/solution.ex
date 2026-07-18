  @spec strip_trailing_comma(String.t()) :: String.t()
  defp strip_trailing_comma(text) do
    case String.ends_with?(text, ",") do
      true -> String.slice(text, 0..-2//1)
      false -> text
    end
  end