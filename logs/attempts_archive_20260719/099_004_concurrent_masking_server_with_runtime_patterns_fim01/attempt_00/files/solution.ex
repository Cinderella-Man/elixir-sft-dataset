  defp scrub(state, string) do
    builtins = [
      {@cc_regex, &mask_cc/1},
      {@ssn_regex, @ssn_replacement},
      {@email_regex, &mask_email/1}
    ]

    Enum.reduce(builtins ++ state.patterns, {string, 0}, fn {regex, rep}, {str, count} ->
      matches = length(Regex.scan(regex, str))
      {Regex.replace(regex, str, rep), count + matches}
    end)
  end