  defp build_item(name, description, raw_tags) do
    tags =
      case raw_tags do
        nil -> []
        ""  -> []
        str ->
          str
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
      end

    %{name: String.trim(name), description: String.trim(description), tags: tags}
  end