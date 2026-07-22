  def filename(input, opts \\ []) when is_binary(input) do
    mode = Keyword.get(opts, :mode, :lenient)

    no_null = String.replace(input, "\0", "")
    no_sep = no_null |> String.replace("/", "") |> String.replace("\\", "")
    filtered = String.replace(no_sep, ~r/[^a-zA-Z0-9_\-.]/, "")
    collapsed = String.replace(filtered, ~r/\.{2,}/, ".")
    trimmed = String.trim(collapsed, ".")

    if trimmed == "" do
      {:error, [:empty]}
    else
      violations =
        []
        |> maybe(String.contains?(input, "\0"), :removed_null_bytes)
        |> maybe(String.contains?(input, "/") or String.contains?(input, "\\"),
          :removed_path_separators)
        |> maybe(filtered != no_sep, :removed_illegal_chars)
        |> maybe(collapsed != filtered, :collapsed_dots)
        |> maybe(trimmed != collapsed, :trimmed_dots)

      finalize(mode, trimmed, violations)
    end
  end