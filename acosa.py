#!/usr/bin/env python3

from __future__ import annotations

import argparse
import dataclasses
import enum
import logging
import os
import pathlib
import re
import string
import subprocess
import sys
import typing

import pydantic
import yaml

import colorlog



logger = colorlog.get_logger(__name__, logging.StreamHandler())

ACOSA_DIR = pathlib.Path(__file__).parent
VARIABLE_RE = re.compile(r"\$\w+")


class Variable(pydantic.BaseModel):
    name: str
    value: str
    export: bool = False
    command: bool = False


@dataclasses.dataclass
class VariablePool:
    pool: dict[str, Variable]

    def add_variable(self, variable: Variable) -> typing.Self:
        for hit in VARIABLE_RE.findall(variable.value):
            if (v := self.pool.get(hit)) is None:
                raise ValueError(f'variable "{hit}" is not set')

            variable.value = variable.value.replace(hit, v.value)

        if variable.command:
            variable.value = subprocess.run(
                variable.value, capture_output=True, shell=True
            ).stdout.decode()

        self.pool[f"${variable.name}"] = variable

        return self

    def make_export(self) -> dict[str, str]:
        return {v.name: v.value for v in self.pool.values() if v.export}

    def update(self, new: VariablePool) -> None:
        self.pool.update(new.pool)


class VariableModel(pydantic.BaseModel):
    variables: list[Variable] | None = None

    _pool: VariablePool = VariablePool(dict())

    def unwrap_vars(self, parent: VariablePool | None = None) -> typing.Self:
        self.variables = self.variables or []

        if parent is not None:
            self._pool.update(parent)

        [self._pool.add_variable(v) for v in self.variables]

        return self


class ServiceError(Exception):
    pass


class ServiceApiError(ServiceError):
    pass


@dataclasses.dataclass
class ServiceResult:
    service: Service
    content: str
    returncode: int


class ServiceName(enum.StrEnum):
    INIT_BASE = "init-base.sh"
    GET_ROOTFS = "get-rootfs.sh"
    CONVERT_ROOTFS = "convert-rootfs.sh"
    BUILD_QCOW2 = "build-qcow2.sh"
    BUILD_ISO = "build-iso.sh"
    CHECKOUT = "checkout.sh"
    APT = "apt.sh"
    MAKE_COMMIT = "make-commit.sh"
    BUILDSUM = "buildsum.py"
    PKGDIFF = "pkgdiff.py"
    BUTANE = "butane.sh"
    SKOPEO_COPY = "skopeo-copy.sh"
    FORWARD_ROOT = "forward-root.sh"
    SIGN = "sign.sh"
    COMPRESS = "compress.sh"
    ECHO_TEST = "test-echo.sh"
    PULL_LOCAL = "pull-local.sh"


class Service(VariableModel):
    name: ServiceName
    args: dict[str, str]
    with_print: bool = False
    as_root: bool = False
    skip: bool = False

    def unwrap_args(self) -> typing.Self:
        for karg, varg in self.args.items():
            for hit in VARIABLE_RE.findall(varg):
                if (v := self._pool.pool.get(hit)) is None:
                    raise ValueError(f'variable "{hit}" is not set')

                varg = varg.replace(hit, v.value)

            self.args[karg] = varg

        return self

    def _run_proc(self, *args: str, **kwargs: typing.Any) -> subprocess.Popen:
        """return the service (bash script) process"""

        cur_dir = pathlib.Path(__file__).parent.joinpath("scripts")
        filename = cur_dir.joinpath(self.name)

        args = " ".join(args)

        export = self._pool.make_export()

        prefix = ""
        if self.as_root:
            if (password := os.getenv("PASSWORD")) is None:
                raise ServiceError(
                    f"A password is required for {self.name} service to work, specify it in the PASSWORD variable"
                )
            prefix = f"echo {password} | sudo -SE PYTHONPATH={ACOSA_DIR}"

        cmd = f"{prefix} {filename} {args}"
        opts = {
            "stdout": subprocess.PIPE,
            "stderr": subprocess.PIPE,
            "env": dict(os.environ, **export),
            "shell": True,
        }
        opts.update(kwargs)

        return subprocess.Popen(cmd, **opts)

    def api(self) -> string.Template:
        """return the service api template"""

        if (proc := self._run_proc("-a")).wait() != 0:
            output = proc.stderr.read().decode().strip("\n")
            raise ServiceApiError(f'failed to get "{self.name}" service API ({output})')

        args = proc.stdout.read().decode().strip("\n")

        return string.Template(args)

    def run(self, parent: VariablePool) -> ServiceResult:
        """start the service and return result"""

        api = self.unwrap_vars(parent).unwrap_args().api().substitute(self.args)
        content = ""

        with self._run_proc(api, stderr=subprocess.STDOUT) as proc:
            for output in proc.stdout:
                output = output.decode()
                # store output to variable for later return
                content += output

                if self.with_print:
                    print(output, end="")

        return ServiceResult(self, content, proc.returncode)


class Task(VariableModel):
    services: list[Service]

    def run(self) -> None:
        for service in self.services:
            if service.skip:
                continue

            logger.info(f'service "{service.name}" started')
            result = service.run(self._pool)

            if result.returncode != 0:
                logger.fatal(f'service "{service.name}" failed')
                print(
                    f"\nreturncode: {result.returncode}"
                    f"\n↓ output ↓"
                    f"\n{result.content}"
                )
                sys.exit(1)
            else:
                logger.info(f'service "{service.name}" finished')

    def check_sudo(self) -> typing.Self:
        for service in self.services:
            if service.as_root:
                if (os.getenv("PASSWORD")) is None:
                    raise ServiceError(
                        f"A password is required for {service.name} service to work, specify it in the PASSWORD variable"
                    )
        return self

def main() -> None:
    parser = argparse.ArgumentParser(description="ALT Container OS Assembler")
    parser.add_argument("config", help="ALTCOS yaml config")

    args = parser.parse_args()

    try:
        with open(args.config, "r") as file:
            content = yaml.safe_load(file)
    except (OSError, yaml.scanner.ScannerError) as e:
        logger.fatal(f'failed to read "{args.config}"\n{e}')
        sys.exit(1)

    try:
        Task.model_validate(content).check_sudo().unwrap_vars().run()
    except (ServiceError, pydantic.ValidationError) as e:
        logger.fatal(e)


if __name__ == "__main__":
    main()
