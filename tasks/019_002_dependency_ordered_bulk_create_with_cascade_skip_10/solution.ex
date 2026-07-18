  defp validate(attrs) do
    name = attrs["name"]

    errors =
      cond do
        not is_binary(name) or name == "" -> %{"name" => ["can't be blank"]}
        String.length(name) > 100 -> %{"name" => ["should be at most 100 character(s)"]}
        true -> %{}
      end

    if map_size(errors) == 0, do: nil, else: errors
  end