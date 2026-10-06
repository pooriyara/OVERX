import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:overx/core/models/network.dart';
import 'package:overx/core/stats/network_source.dart';
import 'package:overx/l10n/strings.dart';
import 'package:overx/l10n/strings_provider.dart';
import 'package:overx/theme/app_theme.dart';

/// فاصله‌ی به‌روزرسانیِ خودکارِ فهرست‌ها.
const Duration kNetworkRefreshInterval = Duration(seconds: 2);

/// گروه‌های خروجی و اتصال‌های زنده.
///
/// منبعِ داده بسته به پلتفرم فرق می‌کند و انتخابش در
/// [networkSourceProvider] انجام می‌شود: روی اندروید libbox، روی دسکتاپ
/// Clash API ی sing-box. اگر هیچ‌کدام نباشد (هسته خاموش، یا Xray روی
/// دسکتاپ) صفحه پیامِ توضیحی نشان می‌دهد.
class NetworkPage extends ConsumerStatefulWidget {
  const NetworkPage({super.key});

  @override
  ConsumerState<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends ConsumerState<NetworkPage> {
  Timer? _timer;

  bool _loading = true;
  String? _error;
  List<OutboundGroup> _groups = const <OutboundGroup>[];
  List<ConnectionEntry> _connections = const <ConnectionEntry>[];

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(kNetworkRefreshInterval, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  Future<void> _refresh() async {
    final source = ref.read(networkSourceProvider);
    if (source.kind == NetworkSourceKind.none) {
      if (mounted) {
        setState(() {
          _loading = false;
          _groups = const <OutboundGroup>[];
          _connections = const <ConnectionEntry>[];
        });
      }
      return;
    }
    try {
      final groups = await source.getGroups();
      final connections = await source.getConnections();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _connections = connections;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _select(String groupTag, String outboundTag) async {
    await ref.read(networkSourceProvider).selectOutbound(
          groupTag: groupTag,
          outboundTag: outboundTag,
        );
    // نتیجه بلافاصله در فهرست نمی‌آید؛ یک بار دیگر می‌خوانیم
    await _refresh();
  }

  Future<void> _urlTest(String outboundTag) async {
    await ref.read(networkSourceProvider).urlTest(outboundTag);
    await _refresh();
  }

  Future<void> _close(String id) async {
    await ref.read(networkSourceProvider).closeConnection(id);
    await _refresh();
  }

  Future<void> _closeAll() async {
    await ref.read(networkSourceProvider).closeConnections();
    await _refresh();
  }

  /// پیامِ مناسب برای دلیلِ نبودِ منبع.
  static String _unavailableKey(NetworkSource source) {
    if (source is UnavailableNetworkSource) {
      return switch (source.reason) {
        NetworkUnavailableReason.coreStopped => 'networkStoppedBody',
        NetworkUnavailableReason.xray => 'networkXrayBody',
        NetworkUnavailableReason.other => 'networkUnsupportedBody',
      };
    }
    return 'networkUnsupportedBody';
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final source = ref.watch(networkSourceProvider);

    if (source.kind == NetworkSourceKind.none) {
      return _Message(
        icon: Icons.hub_outlined,
        title: s.t('networkNoData'),
        body: s.t(_unavailableKey(source)),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: <Widget>[
          TabBar(
            tabs: <Tab>[
              Tab(text: s.t('groups')),
              Tab(text: s.t('connections')),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _buildGroups(s),
                _buildConnections(s),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroups(Strings s) {
    if (_loading && _groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return _Message(icon: Icons.error_outline, title: _error!);
    if (_groups.isEmpty) {
      return _Message(icon: Icons.account_tree_outlined, title: s.t('noGroups'));
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        itemCount: _groups.length,
        itemBuilder: (context, i) => _GroupCard(
          group: _groups[i],
          s: s,
          onSelect: _select,
          onTest: _urlTest,
        ),
      ),
    );
  }

  Widget _buildConnections(Strings s) {
    if (_loading && _connections.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) return _Message(icon: Icons.error_outline, title: _error!);
    if (_connections.isEmpty) {
      return _Message(icon: Icons.swap_vert_outlined, title: s.t('noConnections'));
    }

    return Column(
      children: <Widget>[
        _SubHeader(
          label: '${_connections.length}',
          action: TextButton.icon(
            icon: const Icon(Icons.close, size: 16),
            label: Text(s.t('closeAllConnections')),
            onPressed: _closeAll,
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: _connections.length,
              itemBuilder: (context, i) {
                final c = _connections[i];
                return ListTile(
            dense: true,
            leading: Icon(
              c.isClosed ? Icons.link_off : Icons.link,
              size: 18,
              color: c.isClosed ? StatusColors.idle : StatusColors.connected,
            ),
            title: Text(
              c.displayDestination,
              style: const TextStyle(fontSize: 13.5),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${c.protocol} · ${c.outbound}',
              style: const TextStyle(fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    c.totalText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    tooltip: s.t('closeConnection'),
                    onPressed: () => _close(c.id),
                  ),
                ],
              ),
            );
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

/// خطِ بالای یک فهرست: تعداد در یک سمت و یک دکمه در سمتِ دیگر.
class _SubHeader extends StatelessWidget {
  const _SubHeader({required this.label, required this.action});

  final String label;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 8, 2),
      child: Row(
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          action,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.s,
    required this.onSelect,
    required this.onTest,
  });

  final OutboundGroup group;
  final Strings s;
  final void Function(String groupTag, String outboundTag) onSelect;
  final void Function(String outboundTag) onTest;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Card(
        elevation: 0,
        color: scheme.surfaceContainerHighest.withValues(alpha: .45),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      group.tag,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      group.type,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (group.selectable && group.items.isNotEmpty)
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButton<String>(
                        value: group.selectedItem != null ? group.selected : null,
                        isExpanded: true,
                        isDense: true,
                        style: TextStyle(fontSize: 13, color: scheme.onSurface),
                        items: group.items
                            .map(
                              (item) => DropdownMenuItem<String>(
                                value: item.tag,
                                // تأخير کنارِ نام: بدونِ آن دکمه‌ی
                                // «تست تأخير» نتيجه‌ای ندارد که ديده شود
                                child: Text(
                                  '${item.tag} · ${item.delayText}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) onSelect(group.tag, value);
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.network_ping, size: 18),
                      tooltip: s.t('urlTest'),
                      onPressed: () => onTest(group.selected),
                    ),
                  ],
                )
              else
                Text(
                  '${s.t('notSelectable')} · ${group.items.length} ${s.t('items')}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, this.body});

  final IconData icon;
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (body != null) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
