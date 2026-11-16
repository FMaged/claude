"""Merges GitLab CI files the way GitLab does, checks the result, and writes it as JSON.

Usage: check-gitlab-ci.py --out DIR [--project PATH=DIR]... FILE...

Resolves include:local and include:project (from the mapped folders) and extends,
then checks that every job has tags, a known stage, no only/except, and needs that
exist. The JSON files in DIR are for check-jsonschema, which cannot see hidden jobs.
"""
import argparse
import json
import pathlib
import sys

import yaml

GLOBAL_KEYS = {"default", "include", "stages", "variables", "workflow", "image", "services",
               "cache", "before_script", "after_script", "spec"}


def merge(base, override):
    # Hashes merge deeply; anything else, lists included, is replaced.
    if isinstance(base, dict) and isinstance(override, dict):
        out = dict(base)
        for key, value in override.items():
            out[key] = merge(base.get(key), value)
        return out
    return override


def load(path, root, projects):
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    includes = data.pop("include", [])
    merged = {}
    for item in includes if isinstance(includes, list) else [includes]:
        if isinstance(item, str):
            item = {"local": item}
        if "local" in item:
            merged = merge(merged, load(root / item["local"].lstrip("/"), root, projects))
        elif "project" in item:
            project_root = projects[item["project"]]
            files = item["file"] if isinstance(item["file"], list) else [item["file"]]
            for name in files:
                merged = merge(merged, load(project_root / name.lstrip("/"), project_root, projects))
        else:
            raise SystemExit(f"{path}: unsupported include {item}")
    return merge(merged, data)


def resolve(name, config, seen=()):
    job = dict(config[name])
    parents = job.pop("extends", [])
    result = {}
    for parent in parents if isinstance(parents, list) else [parents]:
        if parent not in config or parent in seen:
            raise SystemExit(f"{name}: extends unknown or circular '{parent}'")
        result = merge(result, resolve(parent, config, seen + (name,)))
    return merge(result, job)


def check(path, root, projects):
    config = load(path, root, projects)
    jobs = {name: resolve(name, config) for name in config
            if name not in GLOBAL_KEYS and not name.startswith(".")}
    stages = [".pre", *config.get("stages", ["build", "test", "deploy"]), ".post"]
    problems = []
    for name, job in jobs.items():
        if not job.get("tags"):
            problems.append(f"{name}: no tags")
        if job.get("stage", "test") not in stages:
            problems.append(f"{name}: stage '{job.get('stage')}' is not in stages")
        problems += [f"{name}: uses {key}, not rules" for key in ("only", "except") if key in job]
        for need in job.get("needs", []):
            target = need["job"] if isinstance(need, dict) else need
            if target not in jobs:
                problems.append(f"{name}: needs unknown job '{target}'")
    out = {key: config[key] for key in config if key in GLOBAL_KEYS}
    return {**out, **jobs}, problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True, type=pathlib.Path)
    parser.add_argument("--project", action="append", default=[])
    parser.add_argument("files", nargs="+", type=pathlib.Path)
    args = parser.parse_args()
    projects = dict(item.split("=", 1) for item in args.project)
    projects = {name: pathlib.Path(folder) for name, folder in projects.items()}
    failed = False
    for path in args.files:
        # A file's include:local paths start at the root of its repo: the mapped folder it is in.
        root = next((p for p in projects.values() if p.resolve() in path.resolve().parents), path.parent)
        merged, problems = check(path, root, projects)
        for problem in problems:
            print(f"{path}: {problem}")
        failed = failed or bool(problems)
        name = str(path).replace("/", "_").lstrip("._") + ".json"
        (args.out / name).write_text(json.dumps(merged, indent=1), encoding="utf-8")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
