# Read this section before submitting

- Keep the PR title and body suitable as the final merge or squash commit
  message.
- Start the body with a short paragraph beginning `This PR ...`.
- Summarize the problem and useful outcome in the body itself; links to issues
  or discussions are not a substitute for the summary.
- Put questions, local notes, and extra review coordination in comments rather
  than the PR description.
- When branch policy requires `Backport ...` lines, draft PRs may use
  `pending`; ready PRs must use `#<pr>` or `exempt: <reason>` for each line.
  PRs retiring the oldest maintained lines use `release-line retirement` for
  those lines.
- If the PR requires paired backports, prefer a merge commit when landing so
  cherry-pick source commits remain in default-dev history. Squash is fine for
  PRs with all backports exempt.
- Remove this instruction block, up to and including the `---`, before
  submitting.

---

This PR <short summary of the problem solved and useful outcome>.

<Optional: one short paragraph or a few bullets with the main behavior or
maintainer-visible changes. Avoid module-by-module implementation inventory.>
