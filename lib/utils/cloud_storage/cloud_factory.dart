import 'cloud_profiles.dart';
import 'cloud_provider.dart';

export 'cloud_profiles.dart' show
    CloudProfile,
    CloudProfileStore,
    CloudSyncMode,
    cloudAutoSyncEnabled,
    newProfileId;

/// Build a [CloudStorageProvider] from the active (or default) profile.
///
/// Legacy single `cloudProvider` / `cloudConfig` / `webdav` settings are
/// migrated into [CloudProfileStore] on first access.
CloudStorageProvider? buildCloudProviderFromSettings() {
  final profile = CloudProfileStore.activeProfile();
  return profile?.buildProvider();
}
