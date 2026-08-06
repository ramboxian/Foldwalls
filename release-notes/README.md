# Foldwalls release notes

Create one plain-text file per version, for example `0.3.0.txt`. The release
script embeds its contents in `appcast.xml`, so the same notes appear in GitHub
Releases and inside Foldwalls.

Prepare a build without publishing:

```sh
scripts/release.sh 0.3.0 release-notes/0.3.0.txt
```

Publish after review:

```sh
scripts/release.sh 0.3.0 release-notes/0.3.0.txt --publish
```

Publishing requires GitHub CLI (`gh`) to be installed and signed into the
`ramboxian` account. The Sparkle private signing key stays in the macOS
Keychain and is never committed to Git.
