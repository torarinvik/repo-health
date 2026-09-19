# Elisa implementation style

Follow the sibling `elisa-engine`, particularly `src/runtime/clock.elisa`:
functions yield their final expression, value construction lives in block
expressions, and loops keep their counters and accumulators in their headers.
The compiler's `docs/119_expression_unification.md` defines these forms.

Expose the result needed by the surrounding code. Keep calculation scratch,
temporary buffers, and intermediate flags inside that result's block. Keep
independent processing stages in separate blocks. A simple expression needs
no additional block.

```elisa
month: i64 =
    y: mutable i64 = 0
    m: mutable i64 = 0
    d: mutable i64 = 0
    rh_civil_from_days(t / 86400, &y, &m, &d)
    rh_month_index(y, m)

total: u64 =
    for i in 0..<counts.count |total: u64 = 0| -> total:
        total <- total + counts[i]
```

Yield multiple loop results together when they are both needed. Capture outer
mutables explicitly when a value block or loop changes them. Use postfix
guards for early exits. Retain named mutable buffers when existing APIs need
mutable references. An owning buffer must outlive every borrowed view or C
pointer into it; do not hide the owner in a block that yields only its pointer.

Prefer the standard library when its contract fits:

- `bytes_view`, `string_view_slice`, `string_view_eq`, and `string_views_eq`
  for bounded byte comparisons. Reject invalid input ranges before slicing;
  standard slices clamp their bounds.
- `sview_starts_with` and `sview_find_byte` for prefix and byte searches.
- `.extend(bytes_view(source))` for complete byte-buffer copies.
- `hash_sview` for the existing FNV-1a evidence digest and `sort` for numeric
  count ordering.
- `read_entire_file` and `write_entire_file` for file contents, retaining the
  repository's size limit and explicit error mapping.

Keep domain contracts that these helpers do not replace: exact integer JSON
parsing, checked rational arithmetic, version-range interpretation, resource
bounds, and the XOR-accumulating signature comparison. The decimal writer
also avoids the extra allocation and formatting capability required by the
standard C-backed integer-to-string routines.

The pinned stage1 snapshot needs a named `catch` result before the function
tail. Some calls with reference arguments also require a typed local result
before a block tail to avoid a spurious structural-shareability diagnostic.
Keep those narrow workarounds; do not disable semantic checks.

Run `bash tools/check.sh` after refactors. It verifies the local oracles,
canonical output fixtures, adapters, storage, CLI paths, and benchmark gates.
