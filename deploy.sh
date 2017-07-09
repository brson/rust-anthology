#!/bin/bash

set -ev

if [ -z "${TRAVIS_BRANCH:-}" ]; then
    echo "This script may only be run from Travis!"
    exit 1
fi

if [ "$TRAVIS_BRANCH" != "master" ]; then
    echo "This commit was made against '$TRAVIS_BRANCH' and not master! No deploy!"
    exit 0
fi

if [ ! -d "out" ]; then
    echo "Run build.sh first"
    exit 1
fi

echo "Committing book directory to gh-pages branch"
REV=$(git rev-parse --short HEAD)

cd out

git init
git remote add upstream "https://${GH_TOKEN}@github.com/brson/rust-anthology.git"
git config user.name "Rust Anthology"
git config user.email "banderson@mozilla.com"
git add -A .
git commit -qm "Build Rust Anthology at ${TRAVIS_REPO_SLUG}@${REV}"

echo "Pushing gh-pages to GitHub"
git push -q upstream HEAD:refs/heads/gh-pages --force
