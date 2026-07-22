def sql_identifier(input, opts \\ []) when is_binary(input) do
  mode = Keyword.get(opts, :mode, :lenient)
  stripped = String.replace(input, ~r/[^a-zA-Z0-9_]/, "")

  if stripped == "" do
    {:error, [:empty]}
  else
    removed = if stripped != input, do: [:removed_illegal_chars], else: []

    {cleaned, prefixed} =
      if String.match?(stripped, ~r/\A[0-9]/) do
        {"_" <> stripped, [:prefixed_digit_start]}
      else
        {stripped, []}
      end

    finalize(mode, cleaned, removed ++ prefixed)
  end
end