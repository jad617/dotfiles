#!/usr/bin/env python3
"""Merge the repo's Caelestia shell.json into the live one, keeping UI changes.

    caelestia-merge.py <repo shell.json> <live shell.json> <base file>

Caelestia rewrites the live ~/.config/caelestia/shell.json when settings change
in its UI, so it can't be a symlink. This is a 3-way merge per setting (a JSON
path down to a non-object value; lists count as one value), against <base>:
the repo file as it was at the last merge.

  - a setting the repo added or changed since <base>   -> written to live
  - a setting the repo removed since <base>            -> removed from live,
    unless it was changed in the UI since (then it stays)
  - a setting the repo didn't touch                    -> live keeps its value

No <base> yet (first run): every repo setting is written. Nothing is ever
written into the repo: data only flows repo -> live. Prints each change.
"""
import json
import os
import sys


def flatten(d, prefix=()):
    out = {}
    for k, v in d.items():
        if isinstance(v, dict) and v:
            out.update(flatten(v, prefix + (k,)))
        else:
            out[prefix + (k,)] = v
    return out


def set_path(d, path, value):
    for k in path[:-1]:
        if not isinstance(d.get(k), dict):
            d[k] = {}
        d = d[k]
    d[path[-1]] = value


def del_path(d, path):
    parents = []
    for k in path[:-1]:
        if not isinstance(d.get(k), dict):
            return
        parents.append((d, k))
        d = d[k]
    d.pop(path[-1], None)
    for parent, k in reversed(parents):  # drop objects left empty
        if parent[k]:
            break
        del parent[k]


def load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except FileNotFoundError:
        return default


def main():
    repo_path, live_path, base_path = map(os.path.abspath, sys.argv[1:4])
    repo = load(repo_path, None)
    if repo is None:
        sys.exit(f"caelestia-merge: no {repo_path}")
    live = load(live_path, {})
    base = load(base_path, {})
    r, b = flatten(repo), flatten(base)
    lv = flatten(live)
    name = lambda p: ".".join(p)

    changes = []
    for p, v in r.items():
        if (p not in b or b[p] != v) and lv.get(p, object()) != v:
            set_path(live, p, v)
            changes.append(f"set     {name(p)} = {json.dumps(v)}")
    for p, v in b.items():
        if p not in r and p in lv:
            if lv[p] == v:
                del_path(live, p)
                changes.append(f"removed {name(p)}")
            else:
                changes.append(f"kept    {name(p)} (removed from the repo, but changed in the UI)")

    if any(not c.startswith("kept") for c in changes):
        os.makedirs(os.path.dirname(live_path), exist_ok=True)
        tmp = live_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(live, f, indent=2)
            f.write("\n")
        os.replace(tmp, live_path)  # atomic: Caelestia never reads half a file
    os.makedirs(os.path.dirname(base_path), exist_ok=True)
    with open(base_path, "w") as f:
        json.dump(repo, f, indent=2)
        f.write("\n")

    print("\n".join(f"  {c}" for c in changes) if changes else "  already up to date")


if __name__ == "__main__":
    main()
