#! /bin/bash
set -e

BUMP="${1:-patch}"   # patch | minor | major

# ── Read current version ──────────────────────────────────────────────────────
CURRENT=$(grep 'VERSION =' lib/tracelit/version.rb | awk -F'"' '{print $2}')
MAJOR=$(echo "$CURRENT" | cut -d. -f1)
MINOR=$(echo "$CURRENT" | cut -d. -f2)
PATCH=$(echo "$CURRENT" | cut -d. -f3)

# ── Compute next version ──────────────────────────────────────────────────────
case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
  *)
    echo "Usage: ./release.sh [patch|minor|major]"
    exit 1
    ;;
esac

VERSION="${MAJOR}.${MINOR}.${PATCH}"
TAG="v${VERSION}"

echo "Releasing Tracelit Ruby SDK ${TAG}..."

# ── Preflight checks ──────────────────────────────────────────────────────────
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Error: uncommitted changes present. Commit or stash them before releasing."
  exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
  echo "Error: releases must be cut from main (current branch: ${BRANCH})."
  exit 1
fi

git fetch origin main --quiet
if ! git merge-base --is-ancestor origin/main HEAD; then
  echo "Error: local main is behind origin/main. Run 'git pull' first."
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Error: tag ${TAG} already exists."
  exit 1
fi

# ── Bump version file ─────────────────────────────────────────────────────────
sed -i '' "s/VERSION = \"${CURRENT}\"/VERSION = \"${VERSION}\"/" lib/tracelit/version.rb
echo "Bumped version: ${CURRENT} → ${VERSION}"

# ── Commit the version bump ───────────────────────────────────────────────────
git add lib/tracelit/version.rb
git commit -m "Release ${TAG}"

# ── Tag and push ──────────────────────────────────────────────────────────────
echo "Tagging ${TAG} and pushing to GitHub..."
git tag "$TAG"
git push origin "$TAG"

echo ""
echo "Done! GitHub Actions will now run tests and publish the gem to RubyGems."
echo "Watch: https://github.com/Tracelit-AI/tracelit-ruby/actions"
