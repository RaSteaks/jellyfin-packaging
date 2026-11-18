#!/bin/bash
set -euo pipefail

arch=${1:?Missing Debian architecture}
case "$arch" in
    amd64|arm64) ;;
    *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac

cd /components
exec 9>.update.lock
flock -n 9 || { echo "Another component build is in progress." >&2; exit 1; }
mkdir -p "objects/$arch" sets
# A NAS reboot can leave a partial checkout or export. Only this private staging
# directory is disposable; completed objects are reusable after an interruption.
work=/components/.updater-staging
rm -rf -- "$work"
mkdir "$work"
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/set"
printf '%s\n' "$arch" > "$work/set/architecture"

build_component() {
    local name=$1 repo=$2 commit=$3 recipe_file=$4 output=$5
    local src="$work/$name"
    mkdir "$src"
    git init --quiet "$src"
    # Allow large checkouts to finish, but release startup if an HTTPS proxy
    # stops sending data after the branch lookup has already succeeded.
    git -C "$src" -c http.lowSpeedLimit=1024 -c http.lowSpeedTime=120 \
        fetch --quiet --depth=1 -- "$repo" "$commit"
    git -C "$src" checkout --quiet --detach FETCH_HEAD
    rm -rf -- "$src/.git"

    # Fork-controlled build scripts only need a writable checkout, output and
    # package cache. The updater keeps ownership of the active selection.
    install -d -m 0700 -o jellyfin-build -g jellyfin-build /components/.build-home "$output"
    chown -hR jellyfin-build:jellyfin-build "$src"
    (
        cd "$src" || exit 1
        export HOME=/components/.build-home
        exec setpriv --reuid=jellyfin-build --regid=jellyfin-build --clear-groups \
            --no-new-privs bash "$recipe_file" "$output" "$arch" "$commit"
    ) || return 65
    chown -hR root:root "$output"
    chmod -R go-w "$output"
    case "$name" in
        server) test -x "$output/jellyfin" && test -s "$output/jellyfin.runtimeconfig.json" ;;
        web)    test -s "$output/index.html" ;;
        ffmpeg) test -x "$output/ffmpeg" && test -x "$output/ffprobe" && test -x "$output/jellyfin-disc-info" ;;
    esac || { echo "Incomplete $name build output for $commit." >&2; return 65; }
}

prune_old_generations() {
    local active previous="" generation name object path
    local -A keep_objects=()
    active=$(readlink current) || return 1
    if [[ -f $active/previous ]]; then
        read -r previous < "$active/previous" || return 1
    fi
    # Read all protected links before deleting anything. Links also identify
    # the commit-only object paths used by the original image.
    for generation in "$active" "$previous"; do
        [[ -n $generation ]] || continue
        for name in server web ffmpeg; do
            object=$(readlink "$generation/$name") || return 1
            keep_objects["$object"]=1
        done
    done
    for path in sets/set.*; do
        [[ $path != "$active" && $path != "$previous" ]] || continue
        rm -rf -- "$path" || return 1
    done
    for path in objects/*/{server,web,ffmpeg}/*; do
        [[ -d $path ]] || continue
        [[ -z ${keep_objects[/components/$path]+kept} ]] || continue
        rm -rf -- "$path" || return 1
    done
}

for name in server web ffmpeg; do
    prefix="JELLYFIN_${name^^}"
    repo_var="${prefix}_REPO"
    branch_var="${prefix}_BRANCH"
    repo=${!repo_var:?Missing component repository}
    branch=${!branch_var:?Missing component branch}
    git check-ref-format "refs/heads/$branch"
    if ! head=$(timeout 45 git ls-remote --exit-code --refs -- "$repo" "refs/heads/$branch"); then
        echo "Could not resolve $name branch '$branch'; check its name, network and repository access." >&2
        exit 1
    fi
    read -r commit ref <<< "$head"
    [[ $commit =~ ^[a-f0-9]{40}$ && $ref == "refs/heads/$branch" ]]
    recipe_file="/opt/jellyfin-updater/build-$name.sh"
    checksum=$(cat "$recipe_file" "/opt/jellyfin-updater/$name.toolchain" | sha256sum)
    recipe_digest=${checksum%% *}
    object="objects/$arch/$name/$commit-$recipe_digest"
    if [[ ! -d $object ]]; then
        echo "Building $name from $branch at $commit" >&2
        mkdir -p "objects/$arch/$name"
        build_component "$name" "$repo" "$commit" "$recipe_file" "$work/$name-output"
        mv -T "$work/$name-output" "$object"
    else
        echo "Reusing $name at $commit" >&2
    fi
    ln -s "/components/$object" "$work/set/$name"
    printf '%s %s %s\n' "$name" "$commit" "$recipe_digest" >> "$work/set/commits"
done

if [[ ! -f current/commits || $(cat current/architecture) != "$arch" ]] \
    || ! cmp -s current/commits "$work/set/commits"; then
    # Store the predecessor in the new generation. One atomic rename publishes
    # both the active set and the identity of the set to retain for recovery.
    if [[ -L current ]]; then
        readlink current > "$work/set/previous"
    fi
    set_id=$(mktemp -d sets/set.XXXXXXXX)
    mv -T "$work/set" "$set_id"
    ln -s "$set_id" "$work/next"
    mv -Tf "$work/next" current
    cat current/commits
fi
# Also finish any cleanup interrupted just after a previous activation.
prune_old_generations || echo "Component cleanup incomplete; will retry after the next successful update check." >&2
