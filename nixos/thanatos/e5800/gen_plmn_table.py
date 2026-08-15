#!/usr/bin/env python3
"""Generate the trimmed PLMN table from a mcc-mnc-list.json.

    ./gen_plmn_table.py /path/to/mcc-mnc-list/mcc-mnc-list.json > plmn-names.json

Source data: https://github.com/pbakondy/mcc-mnc-list (MIT), itself derived from
the Wikipedia "Mobile country code" page. The upstream file is ~880K of fields
we do not use; this keeps only what naming needs and lands around a tenth of
that.

WHY THE TABLE IS VENDORED rather than fetched at runtime: a stale or missing
table degrades to showing "310-260" instead of "T-Mobile" -- cosmetic, and
already the designed fallback. An updater would need outbound network in a
service that today only speaks to the router, writable state outside the Nix
store, atomic replacement and schema validation, all to keep a display string
fresh against data that changes administratively a few times a year. It would
also land a third party's unreviewed edits on the lock screen. Regenerating
deliberately, and reading the diff, is the safer trade.

ONE PLMN CAN HAVE SEVERAL ROWS, and they are not duplicates. A network serving
a territory is listed once per region it covers: 234-50 appears for Guernsey,
Jersey and the United Kingdom because JT serves all three under the UK's MCC.
So rows are kept per country rather than collapsed, and the consumer picks
using a country hint. A handful genuinely differ (270-77 is Proximus in BE and
Tango in LU), which is exactly why collapsing would be wrong.
"""
import json
import sys


def trim(records):
    """[upstream record] -> {"mcc-mnc": [{cc, brand, operator, status}, ...]}

    Rows with neither a brand nor an operator carry no name and are dropped;
    a PLMN left with no rows at all is omitted, so the consumer falls back to
    the numeric form.
    """
    out = {}
    for r in records:
        mcc = (r.get("mcc") or "").strip()
        mnc = (r.get("mnc") or "").strip()
        if not mcc or not mnc:
            continue
        brand = (r.get("brand") or "").strip()
        operator = (r.get("operator") or "").strip()
        if not brand and not operator:
            continue
        out.setdefault("{}-{}".format(mcc, mnc), []).append({
            "cc": (r.get("countryCode") or "").strip(),
            "brand": brand,
            "operator": operator,
            "status": (r.get("status") or "").strip(),
        })
    # Sort rows by country code so the generated file is stable across runs and
    # a regeneration diff shows real data changes rather than reordering.
    for rows in out.values():
        rows.sort(key=lambda x: (x["cc"], x["brand"], x["operator"]))
    return out


def main(argv):
    if len(argv) != 2:
        sys.stderr.write(__doc__)
        return 2
    with open(argv[1]) as f:
        records = json.load(f)
    table = trim(records)
    json.dump(table, sys.stdout, sort_keys=True, separators=(",", ":"))
    sys.stdout.write("\n")
    sys.stderr.write("{} PLMNs from {} records\n".format(len(table), len(records)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
