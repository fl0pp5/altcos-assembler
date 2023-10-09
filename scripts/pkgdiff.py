#!/usr/bin/env python3
from __future__ import annotations

import argparse
import dataclasses
import shlex
import json
import pathlib
import sys
import tempfile
import typing
import subprocess
import logging

import rpm
import altcos

import colorlog

logger = colorlog.get_logger(__name__, logging.StreamHandler(), fmt="%(message)s")


PROGRAM_NAME = pathlib.Path(sys.argv[0]).name


@dataclasses.dataclass
class Package:
    __slots__ = ("_header",)

    _header: rpm.hdr

    def __hash__(self) -> int:
        return hash(self.name)

    def __str__(self) -> str:
        return f"{self.name}-{self.version}-{self.release}"

    def __eq__(self, other: Package) -> bool:
        return rpm.versionCompare(self._header, other._header) == 0

    def __lt__(self, other: Package) -> bool:
        return rpm.versionCompare(self._header, other._header) == -1

    def __gt__(self, other: Package) -> bool:
        return rpm.versionCompare(self._header, other._header) == 1

    @property
    def name(self) -> str:
        return self._header[rpm.RPMTAG_NAME].decode()

    @property
    def version(self) -> str:
        return self._header[rpm.RPMTAG_VERSION].decode()

    @property
    def release(self) -> str:
        return self._header[rpm.RPMTAG_RELEASE].decode()

    @property
    def epoch(self) -> int:
        return self._header[rpm.RPMTAG_EPOCH]

    @property
    def summary(self) -> str:
        return self._header[rpm.RPMTAG_SUMMARY].decode()

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "version": self.version,
            "release": self.release,
            "epoch": self.epoch,
            "summary": self.summary,
        }


PackageMapping: typing.TypeAlias = dict[str, Package]
PackageUnwrapMapping: typing.TypeAlias = dict[str, dict[str, str]]


class BDBReader:
    def __init__(self, content: bytes) -> None:
        self.content = content

    @classmethod
    def from_ostree_commit(cls, commit: altcos.Commit) -> BDBReader:
        cmd = shlex.split(
            f"ostree cat {commit} --repo={commit.repo.path} /lib/rpm/Packages"
        )
        content = subprocess.run(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        ).stdout
        return cls(content)

    def read(self) -> PackageMapping:
        with tempfile.TemporaryDirectory(prefix=PROGRAM_NAME) as dbpath:
            db = pathlib.Path(dbpath, "Packages")
            db.write_bytes(self.content)

            if dbpath:
                rpm.addMacro("_dbpath", dbpath)

            pkgs = {
                hdr[rpm.RPMTAG_NAME]: Package(hdr)
                for hdr in rpm.TransactionSet().dbMatch()
            }

            if dbpath:
                rpm.delMacro("_dbpath")

        return pkgs


@dataclasses.dataclass
class UpdateDiff:
    __slots__ = ("new_pkg", "old_pkg")

    new_pkg: Package
    old_pkg: Package

    def to_dict(self) -> PackageUnwrapMapping:
        return {
            "new": self.new_pkg.to_dict(),
            "old": self.old_pkg.to_dict(),
        }


def get_update_diff_list(a: PackageMapping, b: PackageMapping) -> list[UpdateDiff]:
    return [UpdateDiff(a[n], b[n]) for n in a.keys() & b.keys() if a[n] > b[n]]


def get_unique_packages(a: PackageMapping, b: PackageMapping) -> PackageMapping:
    unique_names = set(a.keys()).difference(set(b.keys()))
    return {n: a[n] for n in unique_names}


def main() -> None:
    api = "$stream $repo_root $commit -w"

    if len(sys.argv) == 2 and sys.argv[1] in ["-a", "--api"]:
        print(api)
        sys.exit(0)

    parser = argparse.ArgumentParser(
        description="Collects metadata about reference by commit."
    )
    parser.add_argument("stream", help="ALTCOS stream (e.g. altcos/x86_64/sisyphus/base)")
    parser.add_argument("repo_root", help="ALTCOS repository root")
    parser.add_argument("commit")
    parser.add_argument(
        "-m",
        "--mode",
        choices=[*altcos.Repository.Mode],
        default=altcos.Repository.Mode.BARE.value,
    )
    parser.add_argument("-i", "--indent", type=int)
    parser.add_argument(
        "-w",
        "--write",
        action="store_true",
        help="Write metadata to the version directory.",
    )
    args = parser.parse_args()

    stream = altcos.Stream.from_str(args.repo_root, args.stream)

    if not (repo := altcos.Repository(stream, args.mode)).exists():
        logger.fatal(f'failed to open "{repo.path}" repository')
        sys.exit(1)

    if args.commit == "latest":
        if not (commit := repo.last_commit()):
            logger.fatal(f'failed to get latest commit')
            sys.exit(1)
    else:
        if not (commit := altcos.Commit(repo, args.commit)).exists():
            logger.fatal(f'failed to get "{commit}" commit')
            sys.exit(1)

    pkgs = BDBReader.from_ostree_commit(commit).read()
    installed = [pkg.to_dict() for pkg in pkgs.values()]
    [updated, new, removed] = [[]] * 3

    if (parent := commit.parent) is not None:
        parent_pkgs = BDBReader.from_ostree_commit(parent).read()
        new = [pkg.to_dict() for pkg in get_unique_packages(pkgs, parent_pkgs).values()]
        removed = [
            pkg.to_dict() for pkg in get_unique_packages(parent_pkgs, pkgs).values()
        ]
        updated = [diff.to_dict() for diff in get_update_diff_list(pkgs, parent_pkgs)]

    metadata = {
        "reference": str(stream),
        "version": str(commit.version),
        "description": str(commit.description),
        "commit": str(commit),
        "parent": str(parent) if parent else None,
        "package_info": {
            "installed": installed,
            "new": new,
            "removed": removed,
            "updated": updated,
        },
    }

    if args.write:
        metadata_path = stream.vars_dir.joinpath(
            commit.version.like_path, "metadata.json"
        )
        with open(metadata_path, "w") as file:
            json.dump(metadata, file, indent=args.indent)
    else:
        print(json.dumps(metadata, indent=args.indent))


if __name__ == "__main__":
    main()
