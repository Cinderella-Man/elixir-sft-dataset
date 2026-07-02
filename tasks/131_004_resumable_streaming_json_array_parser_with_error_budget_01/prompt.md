# Resumable Streaming JSON Array Parser with Error Budget

Write me an Elixir module called `ResumableJsonStreamer` that streams a **very
large JSON array file** (think gigabytes) one item at a time, but with two
failure-semantics features the classic streamer lacks: a **strict error budget**
that aborts the run when too many items are malformed, and **resumable
processing** so a re-run can skip past already-processed (or poison) items.

## Public API

Implement a single public function:

```elixir
ResumableJsonStreamer.process(file_path, handler_fn, opts \\ [])
```

- `file_path` is the path to a file on disk.
- `handler_fn` is a one-arity function. For every successfully decoded item that
  is **not skipped by resume**, you call `handler_fn.(item)` exactly once. Its
  return value is ignored.
- `opts` may contain:
  - `:max_errors` — a non-negative integer, or `:infinity` (the default). This
    is the number of malformed items **tolerated**. The stream aborts on the
    error that would push the cumulative error count **above** `:max_errors`.
    So `max_errors: 0` aborts on the first malformed item; `max_errors: 2` keeps
    going through two malformed items and aborts on the third.
  - `:resume_from` — a non-negative integer (default `0`). Skip the first
    `:resume_from` **element lines** entirely: they are not decoded, not passed
    to `handler_fn`, and not counted in `:processed` or `:errors`.

## Element indexing

Only **element lines** count toward indexing: lines that are not blank, not `[`,
and not `]`. They are numbered `1, 2, 3, …` in file order. `:resume_from` skips
element lines whose index is `<= resume_from`. The returned `:last_index` is the
index of the last element line the parser examined.

## Return value

- On a clean run, return `{:ok, stats}`.
- On abort (error budget exceeded), return `{:error, :too_many_errors, stats}`.

`stats` is a map with:

- `:processed` — integer, items successfully decoded and passed to `handler_fn`.
- `:errors` — integer, malformed items encountered (up to and including the one
  that triggered an abort).
- `:elapsed_ms` — number, wall-clock time (use `System.monotonic_time/1`), `>= 0`.
- `:throughput` — float, `processed / (elapsed_ms / 1000)`; `0.0` when
  `elapsed_ms` is `0` (never divide by zero).
- `:last_index` — integer, the index of the last element line examined (`0` if
  none were examined, e.g. an empty array or `resume_from` past the end).
- `:aborted` — boolean, `true` iff the error budget was exceeded.

Because `:last_index` on an abort points at the poison line, a caller can resume
past it with `resume_from: last_index`.

## Input file format

Same one-element-per-line JSON array layout as the classic streamer: first line
`[`, last line `]`, every element line ending in a trailing comma except the
last; empty array is `[` then `]`. For each element line: trim whitespace, strip
a single trailing comma if present, and decode with the standard library `JSON`
module (Elixir 1.18+) so objects become maps with **string keys**.

## Memory constraints

Read lazily with `File.stream!/2` and fold so only a single line (plus its
decoded value) is in memory at a time. Aborting must stop reading early — do not
consume the rest of the file after the budget is blown.

## Constraints

- Use only the Elixir/OTP standard library. No external dependencies.
- Provide the complete module in a single file.