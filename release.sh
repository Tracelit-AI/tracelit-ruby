#! /bin/bash
set -e

VERSION=$(grep 'VERSION =' lib/tracelit/version.rb | awk -F'"' '{print $2}')
TAG="v${VERSION}"

echo "Releasing Tracelit Ruby SDK ${TAG}..."

# Ensure working tree is clean
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Error: uncommitted changes present. Commit or stash them before releasing."
  exit 1
fi

# Ensure we are on main
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
  echo "Error: releases must be cut from main (current branch: ${BRANCH})."
  exit 1
fi

# Ensure main is up to date with origin
git fetch origin main --quiet
if ! git merge-base --is-ancestor origin/main HEAD; then
  echo "Error: local main is behind origin/main. Run 'git pull' first."
  exit 1
fi

# Check the tag doesn't already exist
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Error: tag ${TAG} already exists."
  exit 1
fi

echo "Tagging ${TAG} and pushing to GitHub..."
git tag "$TAG"
git push origin "$TAG"

echo ""
echo "Done! GitHub Actions will now run tests and publish the gem to RubyGems."
echo "Watch the release workflow at: https://github.com/Tracelit-AI/tracelit-ruby/actions"
