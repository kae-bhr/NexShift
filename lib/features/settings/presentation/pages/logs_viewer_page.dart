import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nexshift_app/core/services/log_service.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Page de visualisation des logs
class LogsViewerPage extends StatefulWidget {
  const LogsViewerPage({super.key});

  @override
  State<LogsViewerPage> createState() => _LogsViewerPageState();
}

class _LogsViewerPageState extends State<LogsViewerPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _currentSessionLogs;
  String? _previousSessionLogs;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadLogs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      final currentLogs = await LogService().getCurrentSessionLogs();
      final previousLogs = await LogService().getPreviousSessionLogs();
      setState(() {
        _currentSessionLogs = currentLogs;
        _previousSessionLogs = previousLogs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du chargement des logs: $e')),
        );
      }
    }
  }

  Future<void> _copyToClipboard(String? logs) async {
    if (logs == null) return;
    await Clipboard.setData(ClipboardData(text: logs));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📋 Logs copiés dans le presse-papiers'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildLogContent(String? logs, String emptyMessage) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (logs == null || logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(emptyMessage, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[200],
          child: Row(
            children: [
              Text(
                '${logs.split('\n').length} lignes',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                color: Theme.of(context).colorScheme.primary,
                onPressed: _loadLogs,
                tooltip: 'Actualiser',
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 20),
                color: Theme.of(context).colorScheme.primary,
                onPressed: () => _copyToClipboard(logs),
                tooltip: 'Copier',
              ),
            ],
          ),
        ),
        // Log content
        Expanded(
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black,
              width: double.infinity,
              child: SelectableText(
                logs,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.greenAccent,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Theme.of(context).colorScheme.primary),
        centerTitle: true,
        title: Text(
          'Logs de débogage',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontFamily: KTextStyle.regularTextStyle.fontFamily,
            fontWeight: KTextStyle.regularTextStyle.fontWeight,
          ),
        ),
        toolbarHeight: 40,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.primary,
          tabs: const [
            Tab(text: 'Session courante'),
            Tab(text: 'Session précédente'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLogContent(
            _currentSessionLogs,
            'Aucun log pour la session courante',
          ),
          _buildLogContent(
            _previousSessionLogs,
            'Aucun log pour la session précédente',
          ),
        ],
      ),
    );
  }
}
