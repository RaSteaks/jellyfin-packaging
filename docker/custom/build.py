#!/usr/bin/env python3
"""Snapshot the four forks and build locally without checkout/reset/push."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[2]


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args])


def tree_hash(root):
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if not path.is_file() and not path.is_symlink():
            continue
        digest.update(path.relative_to(root).as_posix().encode() + b"\0")
        digest.update(str(path.lstat().st_mode & 0o777).encode() + b"\0")
        digest.update(path.readlink().as_posix().encode() if path.is_symlink() else path.read_bytes())
        digest.update(b"\0")
    return digest.hexdigest()


def snapshot(repo, destination, baseline, allow_dirty):
    subprocess.run(["git", "-C", str(repo), "merge-base", "--is-ancestor", baseline, "HEAD"], check=True)
    status = git(repo, "status", "--porcelain").decode()
    if status and not allow_dirty:
        raise ValueError(f"Dirty source {repo}; review it and use --allow-dirty to archive it explicitly")
    names = git(repo, "ls-files", "-z", "--cached", "--others", "--exclude-standard").split(b"\0")
    destination.mkdir(parents=True)
    for name in sorted(set(names) - {b""}):
        relative = Path(name.decode())
        source = repo / relative
        # Gitlinks are deliberately excluded: use the sibling fork snapshots.
        if source.is_dir() or not source.exists():
            continue
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.is_symlink():
            if not source.resolve().is_relative_to(repo.resolve()):
                raise ValueError(f"Source symlink escapes repository: {source}")
            target.symlink_to(source.readlink())
        else:
            shutil.copy2(source, target)
    return {"commit": git(repo, "rev-parse", "HEAD").decode().strip(),
            "baseline": baseline, "dirty": bool(status), "tree_sha256": tree_hash(destination)}


def prepare(args):
    lock = json.loads((ROOT / "docker/custom/sources.lock.json").read_text())
    output = args.output.resolve()
    for source in [ROOT, args.server, args.web, args.ffmpeg]:
        if output.is_relative_to(source.resolve()):
            raise ValueError("Output must be outside the source repositories")
    if 'AssemblyVersion("13.0.0")' not in (args.server / "SharedVersion.cs").read_text():
        raise ValueError("This recipe requires the Jellyfin Server 13.0 development line")
    if json.loads((args.web / "package.json").read_text())["version"] != "13.0.0":
        raise ValueError("This recipe requires Jellyfin Web 13.0.0")
    # A snapshot is immutable once prepared. Never erase or reuse an old context.
    output.mkdir(parents=True, exist_ok=False)
    context = output / "context"
    context.mkdir()
    sources = {}
    for key, repo, name in [("server", args.server, "jellyfin-server"),
                            ("web", args.web, "jellyfin-web"),
                            ("ffmpeg", args.ffmpeg, "jellyfin-ffmpeg"),
                            ("packaging", ROOT, "packaging")]:
        sources[key] = snapshot(repo.resolve(), context / name, lock[key], args.allow_dirty)

    official = (context / "packaging/docker/Dockerfile").read_text()
    ffmpeg = (context / "jellyfin-ffmpeg/Dockerfile.in").read_text()
    ffmpeg = ffmpeg.replace("FROM DISTRO", "FROM --platform=linux/amd64 " + lock["debian_image"] + " AS custom-ffmpeg")
    for old, new in {"BUILD_ARCHITECTURE": args.arch, "GCC_RELEASE_VERSION": "14",
                     "LLVM_RELEASE_VERSION": "19", "LLVMSPIRVLIB_RELEASE_VERSION": "19"}.items():
        ffmpeg = ffmpeg.replace(old, new)
    ffmpeg = ffmpeg.replace("COPY . ${SOURCE_DIR}/", "COPY jellyfin-ffmpeg ${SOURCE_DIR}/")
    ffmpeg = ffmpeg.replace("VOLUME ${ARTIFACT_DIR}/", "ENV RELEASE=debian:trixie")
    ffmpeg = ffmpeg.replace('ENTRYPOINT ["/docker-build.sh"]', "RUN /docker-build.sh")
    # Keep upstream global ARGs before every FROM. Only change source wiring and
    # add the package produced from this context's FFmpeg source, never a submodule.
    first_from = official.index("FROM ")
    dockerfile = official[:first_from] + ffmpeg + "\n" + official[first_from:]
    dockerfile += '\nCOPY --from=custom-ffmpeg /dist/deb/*.deb /tmp/custom-ffmpeg/\n'
    dockerfile += 'RUN apt-get update && apt-get install -y --no-install-recommends /tmp/custom-ffmpeg/jellyfin-ffmpeg8_*.deb && rm -rf /tmp/custom-ffmpeg /var/lib/apt/lists/*\n'
    dockerfile += 'COPY sources.json /jellyfin/sources.json\n'
    (context / "Dockerfile").write_text(dockerfile)
    (context / "sources.json").write_text(json.dumps(sources, indent=2) + "\n")
    context_hash = tree_hash(context)
    tag = f"rasteaks/jellyfin:{lock['version']}-{context_hash[:12]}-{args.arch}"
    arch = {"amd64": "x64", "arm64": "arm64"}[args.arch]
    build_args = {"DOTNET_VERSION": "10.0", "DOTNET_SDK_VERSION": lock["dotnet_sdk"],
                  "NODEJS_VERSION": "24", "NODE_IMAGE": lock["node_image"],
                  "DEBIAN_IMAGE": lock["debian_image"], "PACKAGE_ARCH": args.arch,
                  "DOTNET_ARCH": arch, "TARGET_ARCH": args.arch, "IMAGE_ARCH": args.arch,
                  "JELLYFIN_VERSION": "13.0.0", "FFMPEG_PACKAGE": "jellyfin-ffmpeg8=8.1.3-2-trixie"}
    manifest = {"tag": tag, "architecture": args.arch, "context_sha256": context_hash,
                "sources": sources, "build_args": build_args}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"tag": tag, "context_sha256": context_hash, "output": str(output)}, indent=2))


def build(args):
    output = args.output.resolve()
    context = output / "context"
    manifest = json.loads((output / "manifest.json").read_text())
    if tree_hash(context) != manifest["context_sha256"]:
        raise ValueError("Build context changed after prepare; create a new snapshot")
    command = ["docker", "buildx", "build", "--load", "--progress=plain",
               "--platform", "linux/" + manifest["architecture"], "--tag", manifest["tag"],
               "--metadata-file", str(output / "build-metadata.json")]
    for key, value in manifest["build_args"].items():
        command += ["--build-arg", f"{key}={value}"]
    for key, value in manifest["sources"].items():
        command += ["--label", f"org.rasteaks.source.{key}={value['commit']}:{value['tree_sha256']}"]
    command += [str(context)]
    with (output / "build.log").open("w") as log:
        subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, check=True)
    with (output / "image-inspect.json").open("w") as info:
        subprocess.run(["docker", "image", "inspect", manifest["tag"]], stdout=info, check=True)
    print(manifest["tag"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prep = commands.add_parser("prepare")
    prep.add_argument("--arch", choices=["amd64", "arm64"], required=True)
    prep.add_argument("--server", type=Path, default=ROOT.parent / "jellyfin")
    prep.add_argument("--web", type=Path, default=ROOT.parent / "jellyfin-web")
    prep.add_argument("--ffmpeg", type=Path, default=ROOT.parent / "jellyfin-ffmpeg")
    prep.add_argument("--allow-dirty", action="store_true")
    prep.add_argument("--output", type=Path, required=True)
    run = commands.add_parser("build")
    run.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    (prepare if args.command == "prepare" else build)(args)


if __name__ == "__main__":
    main()
