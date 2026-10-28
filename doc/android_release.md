# Android releases for this fork

The Android release workflow runs when `tool/android_release.json` changes on
`glass-cloud`, or when it is started manually. It tests the source, builds all
four APK variants, verifies the application ID and version codes, and compares
every signing certificate to this fork's published 1.7.6 APK before publishing.

The public SHA-256 certificate fingerprint is:

`7cd7e12a9878a39da5aeb5f7e51d7a8198a1b9ee0567ebce583e4d1c55e26f70`

The repository must have the original signing credentials configured as Actions
secrets named `ANDROID_KEYSTORE` (base64-encoded original JKS) and
`ANDROID_KEY_PROPERTIES` (the original Java properties containing `keyAlias`,
`keyPassword`, and `storePassword`). The workflow supplies its own temporary
`storeFile` path. Credentials are never committed or printed.

Generating a new key will not let an installed 1.7.6 APK accept an in-place
upgrade. If either secret is absent or the certificate differs, publication
stops before replacing the latest release. The signing certificate in an APK is
public information and cannot reconstruct the original private signing key.

After a successful build, GitHub's scoped workflow token creates the versioned
release, attaches the four verified APKs and checksums, and marks it as Latest.
Application update checks use this fork's published Latest release, so merging
unreleased code alone does not prompt users to install a nonexistent version.
