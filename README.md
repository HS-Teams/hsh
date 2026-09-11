# hsh

**hsh** is a Bash-compatible shell that adds an optional AI-assisted command path for translating natural-language requests into validated, policy-controlled shell execution plans.

The project is derived from GNU Bash and preserves the traditional Bash execution model while adding a separate Rust-based intelligence layer for planning, policy enforcement, provider integration, context management, and authorization.

> The original GNU Bash README is preserved at [`doc/README`](doc/README).

## Goals

- Preserve Bash compatibility for normal shell input.
- Support explicit natural-language requests through `ai`.
- Keep AI providers interchangeable and independent from execution authority.
- Never execute raw model output through `eval`, `bash -c`, or unrestricted shell-script steps.
- Derive effective capabilities locally from typed execution steps.
- Apply local policy before any AI-mediated execution.
- Keep the Bash/C core as the single canonical OS executor.
- Support multiple LLM providers, including local models.
- Introduce mutation, conversational context, and automatic natural-language routing only after the required safety gates exist.

## Example

Traditional Bash commands continue to work normally:

```bash
hsh$ ls -la
hsh$ git status
hsh$ find . -name '*.c'
```

AI-assisted execution is explicit in the initial releases:

```bash
hsh$ ai "list the five largest files in Downloads"
```

The intended future user experience includes prefixless natural language:

```text
hsh$ liste meus arquivos em Downloads e me diga quais baixei na última semana
```

Automatic natural-language routing is not part of the initial MVP and will remain opt-in.

## Architecture

```text
User
 │
 ▼
hsh Bash/C Frontend
 │
 ├──────────────► Bash Compatibility Core ──────────────► OS
 │                    canonical executor
 │
 └──── IPC ─────► hsh-agent (Rust)
                     │
                     ├── AI Provider
                     ├── Typed Plan Parser
                     ├── Capability Derivation
                     ├── Policy Engine
                     ├── Data-Egress Gate
                     ├── Context Manager
                     └── Authorization
```

### Execution boundary

The architecture has one execution authority:

```text
Bash Compatibility Core / C
```

The Rust agent does **not** provide an alternate `fork`/`exec` path for AI-generated plans.

The agent may:

- interpret natural-language requests;
- call an AI provider;
- parse and validate typed plans;
- derive capabilities;
- apply policy;
- manage bounded context;
- issue authorization artifacts.

The Bash/C core is responsible for actual process, pipeline, redirection, and job-control execution.

## AI provider model

hsh is not tied to a specific LLM vendor.

Providers are adapters behind a common interface and may include:

```text
OpenAI
Ollama
Anthropic
Gemini
Mistral
other future providers
```

Provider output is considered untrusted.

Capabilities and risk decisions returned by a model are hints only. Effective capabilities are recomputed locally before authorization.

## Security model

AI-generated plans are structured and versioned.

Conceptually:

```json
{
  "schema_version": "1.0",
  "steps": [
    {
      "type": "process",
      "program": "find",
      "args": [
        "~/Downloads",
        "-type",
        "f"
      ]
    }
  ]
}
```

Raw model text is never directly passed to:

```text
eval
bash -c
shell_script
```

The initial policy is default-deny and supports only the explicitly enabled read-only capability set.

State-changing operations are introduced only after confirmation and authorization infrastructure is available.

## Canonical milestone sequence

| Milestone | Scope |
|---|---|
| **M0** | Foundation, Bash provenance, protocol baseline, repository layout |
| **M1** | Explicit `ai` command, read-only execution, Policy Engine v1 |
| **M2** | Controlled mutation, confirmation, authorization artifacts |
| **M3** | Bounded typed context and stale-target protection |
| **M4** | Multi-provider and configuration maturity |
| **M5** | Opt-in automatic natural-language routing |
| **M6** | Hardening, platform matrix, packaging, 1.0 |

The first user-meaningful MVP is **M1**.

## Repository documentation

Project architecture and planning documents live under the documentation tree.

Typical documents include:

```text
docs/
├── hsh_SRS.pdf
├── hsh_UML2_Component_Design.pdf
└── hsh_Roadmap.pdf
```

The original Bash documentation is preserved separately:

```text
doc/README
```

See [`doc/README`](doc/README) for the GNU Bash README inherited from upstream.

## Bash baseline

hsh is derived from GNU Bash 5.3.x.

The exact upstream tag/commit used as the project baseline must be pinned during M0 and recorded in the repository.

Upstream Bash:

```text
https://git.savannah.gnu.org/git/bash.git
```

Recommended Git remote arrangement:

```text
origin    -> hsh repository
upstream  -> GNU Bash repository
```

## Building

Until the hsh-specific build layer is introduced, the underlying Bash build system remains the baseline.

Typical upstream bootstrap flow:

```bash
./configure
make
```

Exact supported build commands, prerequisites, and platform-specific requirements are defined as part of M0 and must remain reproducible.

## Project tooling

The repository may use helper scripts for GitHub Projects v2 management.

Examples:

```bash
cards.sh list
cards.sh list --status "In Progress"

cards.sh create   --title "[M1] Implement IPC bridge"   --priority High

cards.sh move --issue 12 --next

cards.sh open
```

These scripts are development tooling and are not part of the hsh runtime.

## Platform strategy

Product targets:

- Linux
- macOS

WSL is a secondary target.

M1 uses one blocking primary platform. The other primary product platform remains smoke/non-blocking until the platform matrix is promoted later in the roadmap.

## Licensing

GNU Bash is distributed under the GNU General Public License.

Because hsh is derived from Bash, modifications to the Bash-derived portion must comply with the applicable GPL obligations.

Third-party Rust crates, provider SDKs, and other dependencies retain their respective licenses.

See the repository licensing and provenance documentation before distributing binaries.

## Project status

Current phase:

```text
M0 — Foundation & Provenance
```

M0 establishes:

- exact Bash upstream baseline;
- primary M1 platform;
- Bash compatibility smoke suite;
- per-session `hsh-agent` lifecycle;
- initial AI provider;
- IPC v1 and ExecutionPlan v1;
- canonical repository layout;
- GPL/provenance distribution checklist.

## Design principles

1. Bash remains Bash unless the user explicitly invokes AI or enables a future routing mode.
2. AI providers cannot execute commands.
3. The model cannot authorize itself.
4. Effective capabilities are derived locally.
5. Policy is default-deny.
6. Every AI-mediated execution uses the canonical Bash/C executor.
7. Context is typed data, not instruction.
8. Raw command output and file contents are not sent to providers by default.
9. Mutation requires explicit policy and authorization.
10. Automatic natural-language routing is introduced only after safety and context boundaries are established.
