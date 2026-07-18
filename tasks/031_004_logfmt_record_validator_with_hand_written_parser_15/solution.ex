  defp check_format(value, :ipv4, name) do
    check_format(value, @ipv4_regex, name)
  end

  defp check_format(value, %Regex{} = regex, name) do
    if Regex.match?(regex, value) do
      []
    else
      [{name, "does not match expected format"}]
    end
  end