# PROJECT STATUS

**GOAL (Kamil 2026-07-19): the existing families as extended and as high
quality as possible — the dataset must be GOLD. When everything below is
done and verified, this file becomes one line: "catch up finished, ready
to generate new tasks." Nothing else belongs here.**

Rules: CONTEXT.md HOW-WE-WORK (two-tier findings, pilots, ledgers,
detached+monitored jobs, one solved item = one commit).

---

## THE GAP LIST (ranked; strike items only when fixed + gated + verified)

**G1. Latent semantic defects — full review of EVERY root (not a
sample).** Rubric pass #2 measured 1 real gold defect per 42
execution-perfect roots; extrapolated ~6-8 more hide in the ~330 roots.
Run `semantic_review` over ALL roots + `rubric_judge` full two-family
pass; triage every finding against the artifacts; `close_gaps` the
confirmed ones; every fix cascades + gets its generator gate (rule 7).

**G2. Weak-assertion tail — strengthen to the 0.6 kill floor
corpus-wide, then make the floor a corpus GATE.** Corpus semantic-mutant
kill ~71%; the 0.6 floor holds at accept for new tasks only. Re-measure
per family (`validate --semantic-mutants`), `strengthen_harnesses` the
tail, re-measure, then promote the floor from report-only to a failing
check in validate/CI.

**G3. Prompt-register monotony.** ~76% of seed prompts open "Write
me…"; every templated shape (tfim/wt/sfim/specfim/tdd/bundlefim) has ONE
frozen register. (a) Templated shapes: deterministic template ROTATION
(3-5 variants each, resync gates re-derive — cheap, no LLM); (b) seed
prompts: LLM register rewrite with mandatory blind re-screen per rewrite
(screen_blind_solve restored). Generator side: rotation wired into the
templates so future mints vary too.

**G4. Harness style debt.** 52 April-era harnesses pin internals via
`:sys.get_state` (`rewrite_reachins`, restored path exists); 142 use
`Process.sleep` — audit each: legitimate (documented timing contract) or
debt (needs injected clock); fix the debt class.

**G5. @doc prose truth on EXISTING tasks.** The DOC TRUTH rule guards
new authoring only. Sweep every gold's @doc behavioral claims against
the prompt contract (the F12 class); un-promised claims either get
prompt sentences + anchored tests (promise-audit machinery) or get cut.

**G6. Family spot-checks (CONTEXT rule 8, both sides).** Structured
detailed READS — not scripts — of sampled families across eras and
shapes: prompt vs gold vs harness coherence, plus reject-ledger spot
checks. Findings feed G1's triage; sampling plan and read notes ledgered.

**G7. Extension: 134 unverified repair-chain pairs.** The last topup
printed `mintable (rejected → accepted) pairs: 223 | minted: {exists:
89, unverified: 134}` — investigate why 134 fail verification; recover
what's honestly recoverable into repair/dialogue data.

**G8. Extension headroom (Kamil to confirm scope):** more variations per
base idea (b=005+) would extend existing families without new ideas —
LLM cost per variation ≈ one base cycle. Flag: is this in-scope
"extension" or already "new tasks"?

**G9. Screen depth for hard families.** S6 = one green blind solve;
keep-class roots carry documented reds. Consider 3-solve consistency on
the ~50 keep/hard roots to sharpen the difficulty metadata the export
carries.

---

**After the list:** full sweeps (perfect+fim+mutants+decontam), export
refresh, README, then the one-liner.

**Waiting on Kamil:** G8 scope; the docs/18 training run (any time — its
measurements can reprioritize G2/G3 spend but Kamil chose gold-first).
