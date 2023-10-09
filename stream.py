#!/usr/bin/env python3
import abc
import argparse
import logging
import sys

import altcos
from gi.repository import GLib

import colorlog

logger = colorlog.get_logger(__name__, logging.StreamHandler(), fmt="%(message)s")


class Handler(abc.ABC):
    @staticmethod
    @abc.abstractmethod
    def handle(args: argparse.Namespace) -> None:
        pass

    @staticmethod
    @abc.abstractmethod
    def fill(parser: argparse.ArgumentParser) -> None:
        pass


class StreamHandler(Handler):
    @staticmethod
    def handle(args: argparse.Namespace) -> None:
        try:
            stream = altcos.Stream.from_str(args.repo_root, args.stream)
        except ValueError as e:
            logger.fatal(e)
            sys.exit(1)

        print(stream.export())

    @staticmethod
    def fill(parser: argparse.ArgumentParser) -> None:
        parser.add_argument(
            "stream", help="ALTCOS repository stream (e.g. altcos/x86_64/sisyphus/base)"
        )
        parser.add_argument("repo_root", help="ALTCOS repository root")
        parser.add_argument(
            "-m",
            "--mode",
            choices=[*altcos.Repository.Mode],
            default=altcos.Repository.Mode.BARE,
            help="OSTree repository mode",
        )

        parser.set_defaults(handle=StreamHandler.handle)


class VersionHandler(Handler):
    @staticmethod
    def handle(args: argparse.Namespace) -> None:
        try:
            stream = altcos.Stream.from_str(args.repo_root, args.stream)
        except ValueError as e:
            logger.fatal(e)
            sys.exit(1)

        try:
            repository = altcos.Repository(stream, args.mode).open()
        except GLib.Error as e:
            logger.fatal(e)
            sys.exit(1)

        if args.commit:
            if (commit := altcos.Commit(repository, args.commit)).exists():
                version = commit.version
            else:
                logger.fatal("No one commit not found")
                sys.exit(1)
        else:
            if (commit := repository.last_commit()) is None:
                if args.next:
                    version = altcos.Version(0, 0, stream.branch, stream.name)
                    print(VersionHandler.apply_view(version, args.view))
                    sys.exit(0)
                else:
                    logger.fatal("No one commit not found")
                    sys.exit(1)
            else:
                version = commit.version

        match args.next:
            case "major":
                version.major += 1
            case "minor":
                version.minor += 1

        print(VersionHandler.apply_view(version, args.view))

    @staticmethod
    def fill(parser: argparse.ArgumentParser) -> None:
        parser.add_argument(
            "-n",
            "--next",
            choices=["major", "minor"],
            help="Version part for increment",
        )
        parser.add_argument("-c", "--commit", help="Commit hashsum")
        parser.add_argument(
            "-v",
            "--view",
            choices=["path", "full", "native"],
            default="native",
            help="Version output view",
        )
        parser.set_defaults(handle=VersionHandler.handle)

    @staticmethod
    def apply_view(version: altcos.Version, view: str) -> str:
        match view:
            case "path":
                version = str(version.like_path)
            case "native":
                version = str(version)
            case "full":
                version = version.full
        return version


class CommitHandler(Handler):
    @staticmethod
    def handle(args: argparse.ArgumentParser) -> None:
        try:
            stream = altcos.Stream.from_str(args.repo_root, args.stream)
        except ValueError as e:
            logger.fatal(e)
            sys.exit(1)

        try:
            repository = altcos.Repository(stream, args.mode).open()
        except GLib.Error as e:
            logger.fatal(e)
            sys.exit(1)

        if (commit := repository.last_commit()) is None:
            logger.error("No one commit not found")
            sys.exit(1)

        print(commit)

    @staticmethod
    def fill(parser: argparse.ArgumentParser) -> None:
        parser.set_defaults(handle=CommitHandler.handle)


def main() -> None:
    parser = argparse.ArgumentParser()
    StreamHandler.fill(parser)

    subparsers = parser.add_subparsers()

    version = subparsers.add_parser("version")
    commit = subparsers.add_parser("commit")

    VersionHandler.fill(version)
    CommitHandler.fill(commit)

    args = parser.parse_args()

    args.handle(args)


if __name__ == "__main__":
    main()
