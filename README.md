Stop giving away your secrets.

# Manifesto

People want to show they're AI experts, so they publish the part that actually makes them good: their heuristics, their review standards, their sequencing, their taste.

> There is a difference between a skill that teaches an AI how to use a product and a skill that teaches an AI how to think like you.

Company skills that teach product usage are useful public infrastructure. They help people get value from a tool faster. They make onboarding easier. They reduce support load. Those are worth spreading.

But skills that expose heuristics, taste metrics, review standards, sequencing, and SOPs are different. Those are not just prompts. They are compressed judgment. They contain decisions a capable operator used to hold in their own head.

In a world where AI providers see all of the prompts and source data, the individual needs an edge.

> The best skills will be the ones that load the right judgment at the right moment: what to notice, what to ignore, what good looks like, what tradeoff to make, when to escalate, when to stop.

---

If you're reading this, like me, you're not an AI doomer. And you're also interested in getting an edge. So, how should the enlightened AI connoisseur think about this?

For the individual.

First, grow your judgment so it can travel across domains instead of staying trapped in one workflow.

> Capture the categories of judgment by generalizing skills from domain-specific areas into generalized heuristics to uncover how you think.

Second, build a system for collecting and curating external skills, then personalizing the ones that actually carry durable judgment.

> Translate cross-domain skills into your theory of mind. Enrich your thinking with other domains of thought.

This repo is a collector of skills that show their work. It is a library of raw material and a staging ground for personalization.

The workflow is simple: collect widely, classify carefully, keep what compounds, personalize what matters, and drop the rest.

## What this repo is

This is a Nix flake plus a small `skill` CLI for managing a local `skills/` library.

It does three things:

1. Keeps skills in a flat local directory: `skills/<skill-name>`
2. Imports skills directly from GitHub URLs
3. Exposes the library as flake data so other tooling can consume it

The repo already contains a curated set of imported skills. Each skill lives in its own directory and must contain a `SKILL.md` file.

More specifically, this repo is a collector of skills that reveal heuristics, taste, and SOPs strongly enough to be worth adapting. The goal is not to keep everything. The goal is to gather candidates, sort them, and turn the good ones into something more personal and more defensible.

## Why this exists

There is a real difference between:

- showing that you use AI
- building durable operator advantage with AI

The first pushes people toward posting their SOPs, heuristics, review patterns, and decision rules in public. The second treats those things like assets.

---

Skills are not just prompts. Good skills contain:

- taste
- sequencing
- escalation logic
- edge-case handling
- domain judgment
- hard-won language for how to think about the work

That is operational IP.

## Curation pipeline

This is the workflow the library is built around:

1. Collect public skills from companies, communities, and individual operators
2. Classify them into product-teaching skills, workflow skills, and judgment skills
3. Keep the ones that contain reusable heuristics, taste, or strong SOP structure
4. Drop the ones that are too narrow, too vendor-specific, or not meaningfully better than the base model
5. Personalize the good ones around your own thresholds, standards, and escalation logic
6. Protect the layer that becomes your edge

## Quick start

Enter the dev shell:

```bash
nix develop
```

List local skills:

```bash
skill list
```

Import a skill from a GitHub repo:

```bash
skill https://github.com/OWNER/REPO
```

Import a specific skill or skills directory from a branch/path:

```bash
skill https://github.com/OWNER/REPO/tree/main/path/to/skill
skill https://github.com/OWNER/REPO/tree/main/path/to/skills
```

Run the structural check:

```bash
nix flake check
```

## How imports work

Imports always land in `skills/<skill-name>`.

If the source path points at a single skill, the imported directory name is derived from the repo or path name.

If the source path contains multiple skills, the importer:

1. Finds every nested `SKILL.md`
2. Flattens them into the local `skills/` directory
3. Skips duplicates that already exist locally
4. Writes a `.source` file so you can trace where each imported skill came from

## Repo structure

```text
.
|-- flake.nix          # flake outputs, package, checks, dev shell
|-- src/skill.sh       # import and listing CLI
|-- tests/check.sh     # structural validation
|-- lists.txt          # source URLs used for curation
`-- skills/            # local skill library
```

## Constraints

Each top-level directory inside `skills/` must:

1. Be uniquely named across the whole library
2. Contain a `SKILL.md`
3. Start `SKILL.md` with YAML frontmatter

Those rules are enforced by `tests/check.sh` and wired into `nix flake check`.
