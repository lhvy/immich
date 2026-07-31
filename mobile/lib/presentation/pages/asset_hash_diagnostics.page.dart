import 'dart:convert';

import 'package:auto_route/auto_route.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/providers/infrastructure/storage.provider.dart';

class HashVariant {
  final String label;
  final String? hash;
  final String? error;
  final List<RemoteAsset> remoteMatches;

  const HashVariant({required this.label, this.hash, this.error, this.remoteMatches = const []});
}

class HashDiagnostics {
  final bool mediaLocationGranted;
  final String? storedChecksum;
  final List<HashVariant> variants;

  const HashDiagnostics({required this.mediaLocationGranted, this.storedChecksum, required this.variants});
}

@RoutePage()
class AssetHashDiagnosticsPage extends ConsumerStatefulWidget {
  final String localAssetId;

  const AssetHashDiagnosticsPage({super.key, required this.localAssetId});

  @override
  ConsumerState<AssetHashDiagnosticsPage> createState() => _AssetHashDiagnosticsPageState();
}

class _AssetHashDiagnosticsPageState extends ConsumerState<AssetHashDiagnosticsPage> {
  late Future<HashDiagnostics> _diagnostics;

  @override
  void initState() {
    super.initState();
    _diagnostics = _load();
  }

  Future<HashDiagnostics> _load() async {
    final api = ref.read(nativeSyncApiProvider);
    final id = widget.localAssetId;
    final localAsset = await ref.read(assetServiceProvider).getLocalAsset(id);

    return .new(
      mediaLocationGranted: await api.hasMediaLocationPermission(),
      storedChecksum: localAsset?.checksum,
      variants: [
        await _variant('Current', () => api.hashAssetCurrent(id)),
        await _variant('setRequireOriginal', () => api.hashAssetOriginal(id)),
        await _variant('File path', () => api.hashAssetFile(id)),
        await _variant('photo_manager', () => _hashWithPhotoManager(id)),
      ],
    );
  }

  Future<HashVariant> _variant(String label, Future<String?> Function() hash) async {
    try {
      final value = await hash();
      if (value == null) {
        return .new(label: label, error: 'No hash returned');
      }
      final remotes = await ref.read(assetServiceProvider).getAllRemoteAssetDebugByChecksum(value);
      return .new(label: label, hash: value, remoteMatches: remotes);
    } catch (error) {
      return .new(label: label, error: error.toString());
    }
  }

  Future<String?> _hashWithPhotoManager(String id) async {
    final file = await ref.read(storageRepositoryProvider).getFileForAsset(id);
    if (file == null) {
      return null;
    }
    final digest = await sha1.bind(file.openRead()).first;
    return base64.encode(digest.bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hash Diagnostics')),
      body: FutureBuilder<HashDiagnostics>(
        future: _diagnostics,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(padding: const .all(16), child: Text('${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final diagnostics = snapshot.data!;
          return ListView(
            padding: const .all(16),
            children: [
              _Field(label: 'Local ID', value: widget.localAssetId),
              _Field(label: 'Stored checksum', value: diagnostics.storedChecksum ?? 'none'),
              _Field(label: 'Media location', value: diagnostics.mediaLocationGranted ? 'granted' : 'denied'),
              const Divider(height: 32),
              ...diagnostics.variants.map(
                (variant) => _VariantTile(variant: variant, storedChecksum: diagnostics.storedChecksum),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _VariantTile extends StatelessWidget {
  final HashVariant variant;
  final String? storedChecksum;

  const _VariantTile({required this.variant, this.storedChecksum});

  @override
  Widget build(BuildContext context) {
    final remoteMatches = variant.remoteMatches;

    return Card(
      margin: const .only(bottom: 8),
      child: Padding(
        padding: const .all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(variant.label, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _Field(label: 'Hash', value: variant.hash ?? variant.error ?? 'none'),
            _Field(label: 'Matches stored', value: variant.hash == storedChecksum ? 'yes' : 'no'),
            _Field(
              label: 'Remote asset',
              value: remoteMatches.isEmpty
                  ? 'no match'
                  : remoteMatches.map((remote) => '${remote.name} (${remote.id})').join('\n'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;

  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: SelectableText(value, style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
          ),
        ],
      ),
    );
  }
}
