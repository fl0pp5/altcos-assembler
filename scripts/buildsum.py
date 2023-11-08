#!/usr/bin/env python3
import argparse
import os
import json
import pathlib
import sys
import typing

import pydantic

import altcos

FormatMapping: typing.TypeAlias = dict[altcos.Format, altcos.Artifact]
PlatformMapping: typing.TypeAlias = dict[altcos.Platform, FormatMapping]
VersionMapping: typing.TypeAlias = dict[str, PlatformMapping]
StreamMapping: typing.TypeAlias = dict[str, VersionMapping]
ArchMapping: typing.TypeAlias = dict[str, StreamMapping]
BranchMapping: typing.TypeAlias = dict[altcos.Branch, ArchMapping]


class Collector:
    def __init__(self, branch: altcos.Branch, storage: str | os.PathLike) -> None:
        self.branch = branch
        self.storage = storage
        self.root = pathlib.Path(self.storage, self.branch)

    def collect_artifact(
        self,
        arch: altcos.Arch,
        stream: str,
        version: altcos.Version,
        platform: altcos.Platform,
        fmt: altcos.Format,
    ) -> altcos.Artifact:
        artifacts = [
            artifact
            for artifact in self.root.glob(
                f"{arch}/{stream}/{version}/{platform}/{fmt}/*"
            )
        ]

        [location, signature, uncompressed, uncompressed_signature] = [None] * 4

        for artifact in artifacts:
            # <branch>/<name>/<version>/<platform>/<format>/<artifact>
            relative_artifact_path = pathlib.Path(*artifact.parts[-7:])

            if artifact.name.endswith(".tar.gz.sig"):
                signature = relative_artifact_path
            elif artifact.name.endswith(".xz"):
                location = relative_artifact_path
            elif artifact.name.endswith(".sig"):
                uncompressed_signature = relative_artifact_path
            else:
                uncompressed = relative_artifact_path

        return altcos.Artifact(
            location, signature, uncompressed, uncompressed_signature
        )

    def collect_format(
        self,
        arch: altcos.Arch,
        stream: str,
        version: altcos.Version,
        platform: altcos.Platform,
    ) -> FormatMapping:
        formats = {}
        for fmt in self.root.glob(f"{arch}/{stream}/{version}/{platform}/*"):
            fmt = altcos.Format(fmt.name)
            formats[fmt] = self.collect_artifact(arch, stream, version, platform, fmt)
        return formats

    def collect_platform(
        self, arch: altcos.Arch, stream: str, version: altcos.Version
    ) -> PlatformMapping:
        platforms = {}
        for platform in self.root.glob(f"{arch}/{stream}/{version}/*"):
            platform = altcos.Platform(platform.name)
            platforms[platform] = self.collect_format(arch, stream, version, platform)
        return platforms

    def collect_version(self, arch: altcos.Arch, stream: str) -> VersionMapping:
        versions = {}
        for version in self.root.glob(f"{arch}/{stream}/*"):
            version_name = f"{self.branch}_{stream}.{version.name}"
            versions[version.name] = self.collect_platform(
                arch, stream, altcos.Version.from_str(version_name)
            )
        return versions

    def collect_stream(self, arch: altcos.Arch) -> StreamMapping:
        streams = {}
        for stream in self.root.glob(f"{arch}/*"):
            streams[stream.name] = self.collect_version(arch, stream.name)
        return streams

    def collect_arch(self) -> ArchMapping:
        architectures = {}
        for arch in self.root.glob("*"):
            arch = altcos.Arch(arch.name)
            architectures[arch.value] = self.collect_stream(arch)
        return architectures

    def collect(self) -> BranchMapping:
        return {self.branch: self.collect_arch()}


class SisyphusBuilds(pydantic.BaseModel):
    sisyphus: typing.Any


class P10Builds(pydantic.BaseModel):
    p10: typing.Any


def main() -> None:
    api = "$branch $storage -w"

    if len(sys.argv) == 2 and sys.argv[1] in ["-a", "--api"]:
        print(api, end="")
        sys.exit(0)

    parser = argparse.ArgumentParser(description="Collects information on the stream.")
    parser.add_argument("branch", choices=[*altcos.Branch])
    parser.add_argument("storage", help="builds storage root")
    parser.add_argument("-w", "--write", action="store_true", help="Write build summary to the root storage")
    parser.add_argument("-i", "--indent", type=int)

    args = parser.parse_args()

    builds = {altcos.Branch.SISYPHUS: SisyphusBuilds, altcos.Branch.P10: P10Builds}

    branch = altcos.Branch(args.branch)
    summary = Collector(branch, args.storage).collect()
    summary = builds[branch].model_validate(summary).model_dump(mode="json")
    

    if args.write:
        summary_path = pathlib.Path(args.storage, f"{args.branch}.json")
        with open(summary_path, "w") as file:
            json.dump(summary, file, indent=args.indent)
    else:
        print(json.dumps(summary, indent=args.indent))

if __name__ == "__main__":
    main()
