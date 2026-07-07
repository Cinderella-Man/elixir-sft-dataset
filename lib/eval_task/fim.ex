defmodule EvalTask.Fim do
  @moduledoc """
  Fill-in-the-middle (FIM) reconstruction.

  A FIM subtask dir (`<a>_<b>_<name>_0N`, N ≥ 2) holds only a `prompt.md` (the whole
  module with one function replaced by a `# TODO` marker) and a `solution.ex` (that
  one function). The parent `<a>_<b>_<name>_01` dir holds the real `test_harness.exs`.

  To test a candidate: extract the skeleton from the FIM `prompt.md`, splice the
  candidate at the marker, and run the parent's harness against the reconstructed
  module. Reconstruction uses the **prompt skeleton** (not the `_01` module), because
  `_01` modules drift after FIM extraction.
  """

  @todo ~r/#\s*TODO/i
  @skeleton ~r/```elixir\n(.*?)\n```/s
  # Openers that begin a spliceable block: Elixir defs AND ExUnit macro blocks
  # (test-fill-in-the-middle blanks a `test`/`describe`/`setup` body, not a `def`).
  @block_opener ~r/^\s*(def|defp|defmacro|defmacrop|test|describe|setup_all|setup|property)\b/

  @doc "The parent `_01` directory for a FIM dir under `tasks/`."
  @spec parent_dir(String.t()) :: String.t()
  def parent_dir(fim_dir) do
    base = Path.basename(fim_dir)
    parent = (base |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")) <> "_01"
    Path.join(Path.dirname(fim_dir), parent)
  end

  @doc """
  The parent `_01` directory for a `tfim_<a>_<b>_<slug>_0N` test-FIM dir: strip the
  `tfim_` prefix, drop the subtask segment, and append `_01`. The parent holds the
  reference `solution.ex` (the module the reconstructed harness runs against).
  """
  @spec test_fim_parent_dir(String.t()) :: String.t()
  def test_fim_parent_dir(tfim_dir) do
    base = Path.basename(tfim_dir) |> String.replace_prefix("tfim_", "")
    parent = (base |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")) <> "_01"
    Path.join(Path.dirname(tfim_dir), parent)
  end

  @doc "True if `dir` is a FIM subtask (no harness of its own, prompt has a TODO marker)."
  @spec fim_dir?(String.t()) :: boolean()
  def fim_dir?(dir) do
    not File.regular?(Path.join(dir, "test_harness.exs")) and
      File.regular?(Path.join(dir, "prompt.md")) and
      String.match?(File.read!(Path.join(dir, "prompt.md")), @todo)
  end

  @doc """
  Reconstruct the full module from a FIM `prompt.md` skeleton and a candidate.

  The candidate may be the bare function, a fenced function, or a whole module
  (if it already contains `defmodule`, it is used verbatim). Returns the module
  source string, or raises if the skeleton/marker cannot be found.
  """
  @spec reconstruct(String.t(), String.t(), boolean()) :: String.t()
  def reconstruct(prompt_md, candidate_raw, force_splice \\ false) do
    candidate = extract_candidate(candidate_raw)

    # The `defmodule` short-circuit is only valid for module-FIM, where a candidate that
    # is a whole module is used verbatim. For test-FIM the candidate is a `test` block
    # that must ALWAYS be spliced into the harness skeleton — even if it contains the
    # substring `defmodule` (an inline module, or a string literal). `force_splice`
    # selects that behaviour.
    if not force_splice and String.contains?(candidate, "defmodule") do
      candidate
    else
      skeleton = extract_skeleton(prompt_md)
      splice(skeleton, candidate)
    end
  end

  @doc "Strip a wrapping ```` ```elixir ```` fence from a model response, if present."
  @spec extract_candidate(String.t()) :: String.t()
  def extract_candidate(raw) do
    case Regex.run(~r/```(?:elixir)?\n(.*?)\n```/s, raw) do
      [_, code] -> code
      _ -> raw
    end
  end

  # Pick the ```elixir fence that CONTAINS the `# TODO` marker, not merely the first
  # fence. A test-FIM prompt has two fenced blocks — the reference module (no TODO)
  # and the harness skeleton (with the TODO) — so "first fence" would wrongly grab the
  # module. For a single-fence (sfim) prompt this still selects that one fence.
  defp extract_skeleton(prompt_md) do
    # Pick the LAST ```elixir fence containing the marker. A test-FIM prompt places the
    # reference module fence first and the harness skeleton (with the injected `# TODO`)
    # last, so "last TODO-fence" robustly selects the harness even if the module fence
    # happens to contain a `# TODO`-shaped line (e.g. a Markdown heading in a @moduledoc).
    # For a single-fence (sfim) prompt this still selects that one fence.
    Regex.scan(@skeleton, prompt_md, capture: :all_but_first)
    |> Enum.map(&hd/1)
    |> Enum.filter(&String.match?(&1, @todo))
    |> List.last()
    |> case do
      nil -> raise "FIM prompt has no ```elixir fence containing a `# TODO` marker"
      code -> code
    end
  end

  @doc """
  Splice a candidate function into a skeleton at the `# TODO` marker.

  Handles both conventions:
  * stub-body — `def SIG do  # TODO  end` → replace the enclosing `def…end`
  * placeholder-line — `#TODO defp foo` → replace just that line
  """
  @spec splice(String.t(), String.t()) :: String.t()
  def splice(skeleton, candidate) do
    lines = String.split(skeleton, "\n")
    marker_idx = Enum.find_index(lines, &String.match?(&1, @todo)) || raise "no # TODO marker"
    marker_line = Enum.at(lines, marker_idx)
    remainder = Regex.replace(~r/^\s*#\s*TODO:?/i, marker_line, "") |> String.trim()

    {lo, hi} =
      if remainder == "" do
        def_idx = scan_up_for_def(lines, marker_idx)
        indent = Regex.run(~r/^(\s*)/, Enum.at(lines, def_idx)) |> hd()
        end_idx = scan_down_for_end(lines, marker_idx, indent)
        # The candidate is the whole gold function INCLUDING its decorators
        # (`@impl`/`@doc`/`@spec`), but scan_up stops at `def`, leaving the skeleton's
        # matching decorators above it — which then duplicate the candidate's and warn
        # (e.g. "redefining @impl attribute"). Extend the replaced range up over any
        # skeleton decorator the candidate re-provides.
        {merge_lo(lines, def_idx, candidate), end_idx}
      else
        {marker_idx, marker_idx}
      end

    (Enum.slice(lines, 0, lo) ++ [candidate] ++ Enum.slice(lines, (hi + 1)..-1//1))
    |> Enum.join("\n")
  end

  # Topmost skeleton line to remove: walk up from just above `def_idx`, absorbing any
  # module-attribute line whose text the candidate also carries at its top (blanks
  # between them are absorbed too). Stops at the first non-decorator / non-duplicate.
  defp merge_lo(lines, def_idx, candidate) do
    cand_attrs =
      candidate
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.drop_while(&(&1 == ""))
      |> Enum.take_while(&String.starts_with?(&1, "@"))
      |> MapSet.new()

    walk_up_dupes(lines, def_idx - 1, def_idx, cand_attrs)
  end

  defp walk_up_dupes(_lines, j, lo, _cand_attrs) when j < 0, do: lo

  defp walk_up_dupes(lines, j, lo, cand_attrs) do
    trimmed = lines |> Enum.at(j) |> String.trim()

    cond do
      trimmed == "" ->
        walk_up_dupes(lines, j - 1, lo, cand_attrs)

      String.starts_with?(trimmed, "@") and MapSet.member?(cand_attrs, trimmed) ->
        walk_up_dupes(lines, j - 1, j, cand_attrs)

      true ->
        lo
    end
  end

  @doc """
  Build a FIM skeleton DETERMINISTICALLY (the inverse of `reconstruct/3`).

  Given the clean parent module (`parent_src`) and a `candidate` (the target
  function's full definition), returns the parent with EXACTLY the candidate's
  clauses replaced by a single `# TODO` stub — every other function left intact.

  This exists because letting a model hand-produce the skeleton (see
  `GenTask.Prompts.fim_candidate/3`) is error-prone: it over-stubs multi-clause
  functions, leaving redundant/duplicate clauses that warn. Building it from the
  parent guarantees `reconstruct(rewrite_skeleton(prompt, build_skeleton(...)), candidate)`
  compiles cleanly.

  Raises if the candidate cannot be located verbatim in the parent (e.g. the
  candidate was edited away from the reference) — callers should rescue and fall
  back to the model's skeleton.
  """
  @spec build_skeleton(String.t(), String.t()) :: String.t()
  def build_skeleton(parent_src, candidate) do
    cand_lines = candidate |> extract_candidate() |> String.split("\n")
    pl = String.split(parent_src, "\n")
    {s, e} = find_candidate_block(pl, cand_lines)

    def_i =
      Enum.find(s..e//1, &Regex.match?(~r/^\s*(def|defp|defmacro|defmacrop)\b/, Enum.at(pl, &1))) ||
        raise "no def in candidate block"

    indent = Regex.run(~r/^(\s*)/, Enum.at(pl, def_i)) |> hd()

    # Drop the candidate's own decorators (`@impl`/`@doc`/`@spec`) from the stub: the
    # candidate re-provides them on reconstruction, so emitting them here would duplicate
    # (and `@doc` heredocs defeat the splice's decorator-dedup). The whole block s..e is
    # replaced by a bare `def SIG do # TODO end`.
    stub = signature_stub(pl, def_i, indent)

    (Enum.slice(pl, 0, s) ++ stub ++ Enum.slice(pl, (e + 1)..-1//1))
    |> Enum.join("\n")
  end

  @doc "Replace the `# TODO`-bearing ```` ```elixir ```` fence in `prompt_md` with `skeleton`."
  @spec rewrite_skeleton(String.t(), String.t()) :: String.t()
  def rewrite_skeleton(prompt_md, skeleton) do
    Regex.replace(~r/```elixir\n(.*?)\n```/s, prompt_md, fn whole, body ->
      if String.match?(body, @todo), do: "```elixir\n#{skeleton}\n```", else: whole
    end)
  end

  # First clause's signature turned into a `<sig> do\n  # TODO\nend` block. Handles both
  # one-liner (`def f(x), do: y`) and block (`def f(x) do … end`) clause forms, and
  # multi-line signatures. Replaces the WHOLE target with ONE stub so a multi-clause
  # candidate doesn't leave a clause complete that the candidate also re-provides.
  defp signature_stub(lines, def_i, indent) do
    {sig_end, oneliner?} =
      Enum.reduce_while(def_i..(def_i + 30), nil, fn i, _ ->
        line = Enum.at(lines, i) || ""

        cond do
          Regex.match?(~r/,\s*do:/, line) -> {:halt, {i, true}}
          Regex.match?(~r/\bdo\s*$/, line) -> {:halt, {i, false}}
          true -> {:cont, nil}
        end
      end) || raise "no do/`, do:` after def"

    sig =
      if oneliner? do
        last = Enum.at(lines, sig_end) |> String.replace(~r/,\s*do:.*$/, " do")
        Enum.slice(lines, def_i, sig_end - def_i) ++ [last]
      else
        Enum.slice(lines, def_i, sig_end - def_i + 1)
      end

    sig ++ ["#{indent}  # TODO", "#{indent}end"]
  end

  # Locate the candidate as a contiguous run in the parent, comparing only non-blank,
  # trimmed lines (indentation- and blank-line-agnostic). Returns the inclusive span.
  defp find_candidate_block(parent_lines, cand_lines) do
    cand = cand_lines |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    if cand == [], do: raise("empty candidate")
    plist = Enum.map(parent_lines, &String.trim/1)
    n = length(parent_lines)

    start =
      Enum.find(0..(n - 1), fn i ->
        Enum.at(plist, i) == hd(cand) and
          plist |> Enum.drop(i) |> Enum.reject(&(&1 == "")) |> Enum.take(length(cand)) == cand
      end) || raise "candidate not found in parent"

    {endi, _} =
      Enum.reduce_while(start..(n - 1), {start, 0}, fn i, {_last, c} ->
        c2 = if Enum.at(plist, i) == "", do: c, else: c + 1
        if c2 >= length(cand), do: {:halt, {i, c2}}, else: {:cont, {i, c2}}
      end)

    {start, endi}
  end

  @doc """
  Produce a mutant of a candidate function: every clause body replaced with
  `raise`. Used by the validator's mutation check — if the parent harness still
  passes with this mutant spliced in, the FIM target is under-tested.
  """
  @spec mutate(String.t()) :: String.t()
  def mutate(candidate) do
    candidate
    |> extract_candidate()
    |> Code.string_to_quoted!()
    |> Macro.prewalk(fn
      {d, m, [head, kw]} when d in [:def, :defp, :defmacro, :defmacrop] and is_list(kw) ->
        if Keyword.has_key?(kw, :do),
          do: {d, m, [head, [do: quote(do: raise("MUTATION"))]]},
          else: {d, m, [head, kw]}

      other ->
        other
    end)
    |> Macro.to_string()
  rescue
    _ -> "raise \"MUTATION\""
  end

  defp scan_up_for_def(lines, from) do
    Enum.reduce_while((from - 1)..0//-1, nil, fn j, _ ->
      if String.match?(Enum.at(lines, j), @block_opener),
        do: {:halt, j},
        else: {:cont, nil}
    end) || raise "no enclosing def/test block above # TODO"
  end

  defp scan_down_for_end(lines, from, indent) do
    Enum.reduce_while((from + 1)..(length(lines) - 1), nil, fn j, _ ->
      if Enum.at(lines, j) == indent <> "end", do: {:halt, j}, else: {:cont, nil}
    end) || raise "no matching end for the stubbed def"
  end
end
