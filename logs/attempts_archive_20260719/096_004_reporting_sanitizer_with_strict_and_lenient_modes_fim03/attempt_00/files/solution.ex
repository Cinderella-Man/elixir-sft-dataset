  def text(input, opts \\ []) when is_binary(input) do
    mode = Keyword.get(opts, :mode, :lenient)

    no_ctrl = String.replace(input, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "")
    trimmed = String.trim(no_ctrl)
    escaped = html_escape(trimmed)

    violations =
      []
      |> maybe(no_ctrl != input, :removed_control_chars)
      |> maybe(trimmed != no_ctrl, :trimmed_whitespace)
      |> maybe(escaped != trimmed, :escaped_html)

    finalize(mode, escaped, violations)
  end