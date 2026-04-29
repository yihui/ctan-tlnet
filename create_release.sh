# Create GitHub release
TAG=$(date +%Y.%m.%d-%H%M)
echo "RELEASE_TAG=$TAG" >> "$GITHUB_ENV"
gh release create "$TAG" \
  --repo "$GITHUB_REPOSITORY" \
  --title "$TAG" \
  --notes "Automated daily sync of CTAN tlnet"

# Upload large files (>24 MB) to GitHub release
touch /tmp/large-files.txt
find "$STAGING_DIR" -type f -size +24M | sort | while IFS= read -r filepath; do
  relpath="${filepath#$STAGING_DIR/}"
  # Replace every / with = to encode the path in a flat filename
  assetname="${relpath//\//=}"
  mv "$filepath" "/tmp/$assetname"
  echo "Uploading $relpath as $assetname ..."
  for attempt in $(seq 1 5); do
    if gh release upload "$RELEASE_TAG" "/tmp/$assetname" \
          --repo "$GITHUB_REPOSITORY" \
          --clobber; then
      echo "$relpath" >> /tmp/large-files.txt
      break
    fi
    if [ "$attempt" -lt 5 ]; then
      echo "Attempt $attempt failed, retrying in 30s..."
      sleep 30
    else
      echo "ERROR: failed to upload $relpath after 5 attempts"
      exit 1
    fi
  done
done

# Compress remainder, upload archive

# Ensure zstd is available
command -v zstd &>/dev/null || sudo apt-get install -y zstd -qq

# Compress everything that remains (should be well under 2 GB)
echo "Compressing $STAGING_DIR ..."
tar -C "$STAGING_DIR" --zstd -cf /tmp/tlnet.tar.zst .
du -sh /tmp/tlnet.tar.zst

# Upload the archive with retry
for attempt in $(seq 1 5); do
  if gh release upload "$RELEASE_TAG" /tmp/tlnet.tar.zst \
        --repo "$GITHUB_REPOSITORY" \
        --clobber; then
    break
  fi
  if [ "$attempt" -lt 5 ]; then
    echo "Attempt $attempt failed, retrying in 30s..."
    sleep 30
  else
    echo "ERROR: failed to upload archive after 5 attempts"
    exit 1
  fi
done

# Generate _redirects and push to repo

# Build a Cloudflare Pages _redirects file for every large file.
# Each line: /rel/path  https://github.com/REPO/releases/download/TAG/rel=path  302
echo "# $(date)" > _redirects
if [ -s /tmp/large-files.txt ]; then
  while IFS= read -r relpath; do
    assetname="${relpath//\//=}"
    echo "/$relpath  https://github.com/$GITHUB_REPOSITORY/releases/download/$RELEASE_TAG/$assetname  302" \
      >> _redirects
  done < /tmp/large-files.txt
fi

git config user.email "github-actions[bot]@users.noreply.github.com"
git config user.name "github-actions[bot]"
git add _redirects
if git diff --staged --quiet; then
  echo "No changes to _redirects — nothing to commit."
else
  git commit -m "Update _redirects for release $RELEASE_TAG [skip ci]"
  # Retry push in case of transient remote conflicts
  for attempt in $(seq 1 3); do
    if git pull --rebase && git push; then
      break
    fi
    [ "$attempt" -lt 3 ] && sleep 10
  done
fi

# Delete old GitHub releases (keep 2 most recent)
gh release list \
  --repo "$GITHUB_REPOSITORY" \
  --limit 100 \
  --json tagName,createdAt \
  --jq 'sort_by(.createdAt) | reverse | .[2:] | .[].tagName' \
| while IFS= read -r tag; do
    echo "Deleting old release: $tag"
    gh release delete "$tag" \
      --repo "$GITHUB_REPOSITORY" \
      --yes \
      --cleanup-tag || true
  done
