#!/usr/bin/env python3
"""Compute the next release, or write its canonical pubspec version."""
import argparse
import json
import re
import subprocess
from pathlib import Path


def parse(value):
    match = re.fullmatch(r'v?(\d+)\.(\d+)\.(\d+)', value)
    if not match:
        raise ValueError(f'Invalid stable version: {value}')
    return tuple(map(int, match.groups()))


def next_version(current, tags, bump='auto'):
    version, number = current.split('+')
    base = parse(version)
    latest = max((parse(t) for t in tags if re.fullmatch(r'v\d+\.\d+\.\d+', t)), default=None)
    if bump == 'auto' and (latest is None or base > latest):
        return version, int(number)
    major, minor, patch = max(base, latest or base)
    if bump == 'major':
        major, minor, patch = major + 1, 0, 0
    elif bump == 'minor':
        minor, patch = minor + 1, 0
    else:
        patch += 1
    return f'{major}.{minor}.{patch}', int(number) + 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--bump', choices=['auto', 'patch', 'minor', 'major'], default='auto')
    parser.add_argument('--write')
    args = parser.parse_args()
    path = Path('app/pubspec.yaml')
    text = path.read_text()
    if args.write:
        if not re.fullmatch(r'\d+\.\d+\.\d+\+\d+', args.write):
            raise ValueError('Invalid pubspec version')
        path.write_text(re.sub(r'^version: .*$', f'version: {args.write}', text, flags=re.M))
        return
    current = re.search(r'^version: (\d+\.\d+\.\d+\+\d+)$', text, re.M).group(1)
    tags = subprocess.check_output(['git', 'tag', '--list', 'v*'], text=True).splitlines()
    version, build = next_version(current, tags, args.bump)
    stable = [t for t in tags if re.fullmatch(r'v\d+\.\d+\.\d+', t)]
    if stable:
        latest_tag = max(stable, key=parse)
        previous = subprocess.check_output(['git', 'show', f'{latest_tag}:app/pubspec.yaml'], text=True)
        previous_build = int(re.search(r'^version: \d+\.\d+\.\d+\+(\d+)$', previous, re.M).group(1))
        build = max(build, previous_build + 1)
    print(json.dumps({'version': version, 'build': str(build), 'tag': f'v{version}'}))


if __name__ == '__main__':
    main()
