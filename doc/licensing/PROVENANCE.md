# hsh License and Provenance Record

Status: M0 engineering baseline

Snapshot date: 2026-09-11

This record establishes the source and license baseline required by
`M0-AC-003` (the canonical identifier for Roadmap `M0-AC-06`). It is an
engineering release control, not legal advice.

## GNU Bash source provenance

| Field | Recorded value |
|---|---|
| Upstream project | GNU Bash |
| Upstream source | `https://git.savannah.gnu.org/git/bash.git` |
| Version | GNU Bash 5.3, patch level 15 |
| Baseline tag | `bash-5.3-baseline` |
| Immutable baseline commit | `b460816602167718f78a6233164e8875f49b75b2` |
| Baseline commit date | 2026-06-10 |
| Baseline subject | `Bash-5.3 patch 15: fix read builtin to avoid cases where -1 is used as an index into the input buffer` |
| Primary license record | [`COPYING`](../../COPYING), GNU GPL version 3 |
| Copyright/author records | [`AUTHORS`](../../AUTHORS) and file-level notices |
| Original upstream README | [`doc/README`](../README) |

At this snapshot, the baseline commit is the merge base between `HEAD` and
`upstream/master`. The first hsh-specific commit is a child of that baseline.
No Bash-derived C or header source differs from the baseline yet; the current
hsh changes are project documentation and development tooling. This statement
must be regenerated from the release commit rather than assumed for a later
release.

The provenance can be checked locally with:

```bash
git rev-parse bash-5.3-baseline^{commit}
git merge-base HEAD upstream/master
git diff --name-status bash-5.3-baseline..HEAD
```

The expected value from the first two commands for this snapshot is:

```text
b460816602167718f78a6233164e8875f49b75b2
```

## License boundary and notices

GNU Bash source files state that Bash is free software under GNU GPL version 3
or, at the recipient's option, a later version. The complete GPL version 3 text
is preserved in [`COPYING`](../../COPYING). Existing copyright, authorship,
warranty, and license notices must remain intact in source and distribution
artifacts.

hsh is derived from GNU Bash. The project must not claim that moving the Rust
agent, bridge, provider adapters, or packaging into a separate process or
package automatically removes GPL obligations. Before any public or commercial
binary distribution, qualified legal review must classify the actual
Bash-derived executable, bridge, Rust agent, provider modules, linkage, IPC,
and packaging design.

No Rust source, Cargo manifest, provider SDK, or provider module exists in this
snapshot. Their licenses and distribution relationships must be added to this
record before they enter a release artifact.

## Corresponding-source obligations

For object-code distribution, the release review must choose and document a
GPL-compliant source-delivery method. The Corresponding Source set must be the
preferred form for modification and include the material needed to generate,
install, run, and modify the covered object code, including build and install
scripts and required interface definitions. Applicable notices and the license
must accompany the distribution, modified versions must be identified, and no
additional restriction may contradict recipients' GPL rights.

The reviewer must also determine whether installation information or any other
GPL section 6 obligation applies to the particular artifact and distribution
channel. A repository URL by itself is not treated as sufficient evidence: the
approved release record must identify the exact source revision and the source
access method paired with the distributed binary.

## Bundled dependency and material inventory

This is the M0 inventory of third-party material already present in the source
tree. File-level notices remain authoritative when they are more specific.

| Component or material | Repository location | Version/source | License evidence | Binary relevance |
|---|---|---|---|---|
| GNU Bash and bundled Bash libraries | repository root, `builtins/`, `lib/{glob,malloc,sh,termcap,tilde}` | Bash 5.3 patch 15 baseline | Root [`COPYING`](../../COPYING), [`AUTHORS`](../../AUTHORS), and file headers; GPL-3.0-or-later notices | Core executable and supporting libraries |
| GNU Readline | `lib/readline/` | Bundled with the Bash baseline | [`lib/readline/COPYING`](../../lib/readline/COPYING) and file headers; GPL-3.0-or-later | Linked by the default interactive build unless configured otherwise |
| GNU gettext/libintl sources | `lib/intl/` | gettext 0.21.1 | `lib/intl/VERSION` and file headers; mixed LGPL-2.1-or-later, GPL-3.0-or-later, and marked generated-code exceptions | Used when the platform does not provide the required implementation |
| bash-completion | `examples/bash-completion/bash-completion-2.5.tar.xz` | 2.5, upstream archive carried by Bash | `COPYING` and source headers inside the archive; GPL-2.0-or-later | Example/optional package, not part of the default shell executable |
| Shellfloat/shellmath example | `examples/shellmath/` | Copyright 2020 Michael Wood | [`examples/shellmath/LICENSE`](../../examples/shellmath/LICENSE); GPL version 3 text and source notice | Example only |
| Bash tests | `tests/` | Bash baseline | [`tests/COPYRIGHT`](../../tests/COPYRIGHT), root [`COPYING`](../../COPYING), and file-level notices | Test material, not part of the installed executable |
| Bash manuals and documentation | `doc/` excluding `doc/sys-design/` | Bash baseline | `doc/fdl.txt`, document notices, and individual permission notices | Documentation distribution only |
| hsh design PDFs and tooling | `doc/sys-design/`, `scripts/` | hsh project additions after the Bash baseline | Project authorship/history; final release classification pending legal review | Not currently linked into a binary |

System libraries, compiler/runtime components, build tools, generated files,
and platform packaging metadata must be captured from the actual release build.
They are intentionally not guessed in this M0 snapshot. Each release must
refresh this inventory from manifests, lockfiles, build output, and the exact
contents of every distributed archive.

## Release control

Public binary distribution is prohibited unless a release-specific copy of
[`DISTRIBUTION_CHECKLIST.md`](DISTRIBUTION_CHECKLIST.md) is completed, approved,
and accepted by `scripts/check-distribution-readiness.sh`. M6 packaging must
invoke that gate before publication; it must not replace or weaken the M0 gate.
