#!/usr/bin/env bash
# Applies sync/settings.json and release immutability, propagates sync/files/ and removes sync/delete.txt paths in every repository tagged with the sync topic through a pull request.
# Requires GH_TOKEN (administration, contents, pull requests and workflows write access); DRY_RUN=true only prints the changes.
set -euo pipefail

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
files_dir="$root_dir/sync/files"
settings_file="$root_dir/sync/settings.json"
branch="sync/org-files"
dry_run="${DRY_RUN:-false}"
owner="${GITHUB_REPOSITORY_OWNER:-pluginsGLPI}"
topic="sync-org-files"
ci_file=".github/workflows/continuous-integration.yml"
default_glpi_version="11.0.x"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

mapfile -t synced_files < <(cd "$files_dir" && find . -type f)
repos="$(gh repo list "$owner" --topic "$topic" --no-archived --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner')"
mapfile -t deleted_paths < <(grep -v -e '^#' -e '^$' "$root_dir/sync/delete.txt")

while read -r repo; do
    [[ -z "$repo" ]] && continue
    name="${repo#*/}"
    repo_dir="$work_dir/$name"

    settings_diff="$(gh api "repos/$repo" | jq -c --slurpfile wanted "$settings_file" '. as $current | $wanted[0] | with_entries(select(.value != $current[.key]))')"
    if [[ "$settings_diff" != "{}" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            echo "$repo: settings that would be applied: $settings_diff"
        else
            gh api --method PATCH "repos/$repo" --input - --silent <<< "$settings_diff"
            echo "$repo: settings applied: $settings_diff"
        fi
    fi
    # Already enabled when enforced by the organization
    if [[ "$(gh api "repos/$repo/immutable-releases" --jq .enabled)" != "true" ]]; then
        if [[ "$dry_run" == "true" ]]; then
            echo "$repo: release immutability would be enabled"
        else
            gh api --method PUT "repos/$repo/immutable-releases" --silent
            echo "$repo: release immutability enabled"
        fi
    fi

    git clone --quiet --depth 1 "https://x-access-token:${GH_TOKEN}@github.com/${repo}.git" "$repo_dir"
    default_branch="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD)"
    git -C "$repo_dir" checkout --quiet -b "$branch"

    # Keep the GLPI version targeted by the repository, plugins migrate at their own pace
    glpi_version="$(grep -oP 'glpi-version:\s*"\K[^"]+' "$repo_dir/$ci_file" 2>/dev/null | head -n 1 || true)"
    # Keep the plugin specific inputs and secrets of the ci job, written after its last common input
    ci_extra="$(sed '1,/db-image: "\${{ matrix.db-image }}"/d' "$repo_dir/$ci_file" 2>/dev/null || true)"
    cp -r "$files_dir/." "$repo_dir/"
    for file in "${synced_files[@]}"; do
        sed -i -e "s/{PLUGIN}/${name}/g" -e "s/{GLPI_VERSION}/${glpi_version:-$default_glpi_version}/g" "$repo_dir/$file"
    done
    if [[ -n "$ci_extra" ]]; then
        printf '%s\n' "$ci_extra" >> "$repo_dir/$ci_file"
    fi
    # Dependabot fails every run on a missing package.json
    if [[ ! -f "$repo_dir/package.json" ]]; then
        awk 'BEGIN { RS = ""; ORS = "" } !/package-ecosystem: "npm"/ { printf "%s%s", sep, $0; sep = "\n\n" } END { print "\n" }' \
            "$repo_dir/.github/dependabot.yml" > "$work_dir/dependabot.yml"
        mv "$work_dir/dependabot.yml" "$repo_dir/.github/dependabot.yml"
    fi
    for path in "${deleted_paths[@]}"; do
        git -C "$repo_dir" rm -r --quiet --ignore-unmatch -- "$path"
    done

    git -C "$repo_dir" add --all
    if git -C "$repo_dir" diff --cached --quiet; then
        echo "$repo: up to date"
        continue
    fi

    if [[ "$dry_run" == "true" ]]; then
        echo "$repo: changes that would be proposed"
        git -C "$repo_dir" --no-pager diff --cached
        continue
    fi

    git -C "$repo_dir" \
        -c user.name="github-actions[bot]" \
        -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
        commit --quiet --message "Sync organization files"
    git -C "$repo_dir" push --quiet --force origin "$branch"

    if [[ "$(gh pr view "$branch" --repo "$repo" --json state --jq .state 2>/dev/null)" == "OPEN" ]]; then
        echo "$repo: pull request updated"
    else
        gh pr create --repo "$repo" --base "$default_branch" --head "$branch" \
            --title "Sync organization files" \
            --body "Automated update from https://github.com/${GITHUB_REPOSITORY:-pluginsGLPI/.github}/tree/main/sync. Do not edit these files in this repository, change them in the source instead."
    fi
done <<< "$repos"
