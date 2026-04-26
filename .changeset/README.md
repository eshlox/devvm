# Changesets

Add a changeset for user-visible changes:

```bash
corepack pnpm run changeset
```

CI opens a release PR from changesets merged to `main`. Merging that release PR creates
the GitHub release.
