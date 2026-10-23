# pluginsGLPI/.github

Default community health files (issue and pull request templates, security policy) for every repository of the organization that does not define its own.

## Organization files sync

Files in `sync/files/` are pushed through a pull request to every non archived repository of the organization tagged with the `sync-org-files` topic; paths listed in `sync/delete.txt` are removed from them.
Repository settings in `sync/settings.json` (any field of the [update a repository](https://docs.github.com/rest/repos/repos#update-a-repository) API) are applied directly to the same repositories, along with release immutability, Dependabot alerts and security updates, and private vulnerability reporting (public repositories only).
The protection of the default branch and of `X.Y/bugfixes` branches is aligned on `sync/branch-protection.json` (body of the [update branch protection](https://docs.github.com/rest/branches/branch-protection#update-branch-protection) API).

### Subscribe a repository

```bash
gh repo edit pluginsGLPI/<repository> --add-topic sync-org-files
```

The repository is picked up on the next run (push on `main` touching `sync/`, weekly schedule, or manual dispatch of the `Sync organization files` workflow).

### Rules

- Edit synced files here, never in the target repositories: local changes are overwritten on the next run.
- `{PLUGIN}` in a synced file is replaced by the target repository name.
- `{GLPI_VERSION}` is replaced by the `glpi-version` currently set in the target continuous integration workflow (`11.0.x` when missing).
- Lines following `db-image` in the target continuous integration workflow (plugin specific inputs and secrets of the `ci` job) are kept.
- The npm entry of `dependabot.yml` is dropped when the target has no `package.json`.
- The manual dispatch runs in dry run mode by default and only prints the changes.
