  defp do_parse("", _allow, acc, :text, buf, _pa),
    do: {[acc, buf], false}

  defp do_parse("", _allow, acc, :tag, buf, _pa),
    # Unclosed tag at EOF — treat as literal text
    do: {[acc, "<", buf], false}

  defp do_parse("<" <> rest, allow, acc, :text, buf, pa),
    do: do_parse(rest, allow, [acc, buf], :tag, "", pa)

  defp do_parse(">" <> rest, allow, acc, :tag, buf, pa) do
    {tag_out, new_pa} = process_tag(buf, allow, pa)
    do_parse(rest, allow, [acc, tag_out], :text, "", new_pa)
  end

  defp do_parse(<<ch::utf8, rest::binary>>, allow, acc, state, buf, pa),
    do: do_parse(rest, allow, acc, state, buf <> <<ch::utf8>>, pa)