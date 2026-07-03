  defp version_for(type, default) do
    cond do
      String.starts_with?(type, @vendor) and String.ends_with?(type, "+json") ->
        type
        |> String.replace_prefix(@vendor, "")
        |> String.replace_suffix("+json", "")

      type in ["application/json", "application/*", "*/*"] ->
        default

      true ->
        nil
    end
  end