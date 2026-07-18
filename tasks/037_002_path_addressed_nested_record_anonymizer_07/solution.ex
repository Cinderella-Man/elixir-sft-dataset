  defp parse_segment(seg) do
    if String.ends_with?(seg, "[]") do
      [{:key, String.trim_trailing(seg, "[]")}, :each]
    else
      [{:key, seg}]
    end
  end