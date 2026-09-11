# hsh Pre-Distribution License and Provenance Checklist

Gate status: PENDING

Release identifier: TBD

Source commit: TBD

Artifact manifest: TBD

Corresponding source location: TBD

Dependency/license report: TBD

Release owner: TBD

Legal reviewer: TBD

Approval date: TBD

This is the version-controlled M0 checklist required by canonical
`M0-AC-003` (Roadmap alias `M0-AC-06`). It is an engineering release gate and
not legal advice.

## Gate rule

Do not publish or otherwise distribute a public or commercial hsh binary while
this template or a release-specific copy is pending. For every release:

1. Copy this file into the release evidence directory.
2. Replace every `TBD` value with release-specific evidence.
3. Complete every required check below.
4. Obtain release-owner and qualified legal-review approval.
5. Change `Gate status` to `APPROVED` only after those approvals.
6. Run `scripts/check-distribution-readiness.sh <completed-checklist>` from the
   exact source commit used to build the artifacts.
7. Archive the approved checklist, dependency report, artifact hashes, and
   legal-review reference with the release.

The publication or packaging workflow must stop when the command exits nonzero.
The M6 release workflow is required to invoke this gate before uploading or
publishing artifacts.

## Required checks

- [ ] `SCOPE-CLASSIFIED` The legal reviewer classified the actual executable, bridge, Rust agent, provider modules, packaging, linkage, and IPC arrangement included in this release.
- [ ] `SOURCE-PROVENANCE` The GNU Bash tag, immutable commit, version, upstream URL, hsh release commit, and build inputs match [`PROVENANCE.md`](PROVENANCE.md) or an approved release update.
- [ ] `MODIFICATIONS-RECORDED` The release identifies modifications relative to the pinned Bash baseline and carries prominent modification notices and relevant dates where required.
- [ ] `COPYRIGHTS-PRESERVED` Copyright, authorship, warranty, attribution, and file-level license notices are preserved in source and packaged artifacts.
- [ ] `GPL-COPY-INCLUDED` The complete applicable GNU GPL text is included with the distributed artifact and remains readily accessible to recipients.
- [ ] `CORRESPONDING-SOURCE-COMPLETE` Corresponding Source includes the exact preferred source, build/install scripts, interface definitions, hsh changes, and other material needed to generate, install, run, and modify the covered object code.
- [ ] `SOURCE-ACCESS-PAIRED` The selected GPL source-delivery method is documented next to the binary, provides equivalent access where required, and has an owner and retention period appropriate to that method.
- [ ] `INSTALLATION-INFORMATION-REVIEWED` The reviewer documented whether GPL installation-information requirements apply and included the required material when they do.
- [ ] `NO-FURTHER-RESTRICTIONS` Distribution terms, signatures, platform controls, service terms, and packaging impose no unreviewed restriction on recipients' applicable GPL rights.
- [ ] `DEPENDENCIES-INVENTORIED` All bundled, linked, vendored, generated, and runtime dependencies were inventoried from the release build, manifests, lockfiles, and archive contents.
- [ ] `THIRD-PARTY-NOTICES-INCLUDED` Every third-party license condition and required notice is satisfied in the binary package, source package, and documentation bundle.
- [ ] `RUST-AND-SDK-LICENSES-REVIEWED` Cargo crates, provider SDKs, native libraries, and feature-selected dependencies are recorded and reviewed, or the evidence explicitly confirms that none are present.
- [ ] `PROCESS-BOUNDARY-NOT-ASSUMED` Approval does not rely on process or package separation alone to declare the Rust agent, bridge, providers, or other modules legally independent from Bash-derived code.
- [ ] `ARTIFACTS-HASHED` The artifact manifest lists a cryptographic digest for every binary and source artifact covered by this approval.
- [ ] `SOURCE-MATCHES-BINARY` The approved source revision and recorded build procedure reproduce or otherwise verifiably correspond to the distributed artifacts.
- [ ] `LEGAL-REVIEW-APPROVED` Qualified legal review approved this specific distribution design and channel; the reviewer, date, and durable review reference are recorded.
- [ ] `RELEASE-OWNER-APPROVED` The release owner verified all evidence, approved publication, and archived this completed record with the release.

## Approval record

The metadata at the top of the release-specific copy is the approval record.
`Artifact manifest`, `Dependency/license report`, and `Corresponding source
location` must point to durable, release-specific evidence. `Legal reviewer`
must include a review reference suitable for later audit. The gate script
rejects this untouched template, pending status, placeholders, missing required
check identifiers, and unchecked items.
