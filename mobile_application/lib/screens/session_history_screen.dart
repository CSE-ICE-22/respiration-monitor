import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../services/session_service.dart';
import '../models/sensor_data.dart';
import '../widgets/charts.dart';

/// Screen showing saved monitoring sessions
class SessionHistoryScreen extends StatefulWidget {
  const SessionHistoryScreen({super.key});

  @override
  State<SessionHistoryScreen> createState() => _SessionHistoryScreenState();
}

class _SessionHistoryScreenState extends State<SessionHistoryScreen> {
  List<SessionMetadata>? _sessions;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
    });

    final sessionService = context.read<SessionService>();
    final sessions = await sessionService.getSavedSessions();

    setState(() {
      _sessions = sessions;
      _isLoading = false;
    });
  }

  Future<void> _deleteSession(SessionMetadata session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Session'),
          content: Text('Are you sure you want to delete the session from ${session.displayName}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      final sessionService = context.read<SessionService>();
      final success = await sessionService.deleteSession(session.filePath);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _loadSessions();
      }
    }
  }

  Future<void> _exportSession(SessionMetadata session) async {
    final sessionService = context.read<SessionService>();
    final csvPath = await sessionService.exportSessionToCsv(session.filePath);

    if (csvPath != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Session exported to:\n$csvPath'),
          action: SnackBarAction(
            label: 'Copy Path',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csvPath));
            },
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to export session'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _viewSession(SessionMetadata session) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SessionDetailScreen(session: session),
      ),
    );
  }

  Future<void> _cleanupOldSessions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Cleanup Old Sessions'),
          content: const Text(
            'This will delete all sessions older than 30 days. '
            'This action cannot be undone.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Cleanup'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      final sessionService = context.read<SessionService>();
      final deletedCount = await sessionService.cleanupOldSessions();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deleted $deletedCount old session(s)'),
            backgroundColor: Colors.green,
          ),
        );
        _loadSessions();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session History'),
        actions: [
          IconButton(
            onPressed: _cleanupOldSessions,
            icon: const Icon(Icons.cleaning_services),
            tooltip: 'Cleanup Old Sessions',
          ),
          IconButton(
            onPressed: _loadSessions,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessions == null || _sessions!.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 64,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No saved sessions',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your monitoring sessions will appear here',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _sessions!.length,
                  itemBuilder: (context, index) {
                    final session = _sessions![index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(
                            Icons.analytics,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        title: Text(session.displayName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Duration: ${session.durationString}'),
                            Text('${session.dataPoints} data points'),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            switch (value) {
                              case 'view':
                                _viewSession(session);
                                break;
                              case 'export':
                                _exportSession(session);
                                break;
                              case 'delete':
                                _deleteSession(session);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'view',
                              child: Row(
                                children: [
                                  Icon(Icons.visibility),
                                  SizedBox(width: 8),
                                  Text('View'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'export',
                              child: Row(
                                children: [
                                  Icon(Icons.file_download),
                                  SizedBox(width: 8),
                                  Text('Export to CSV'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        onTap: () => _viewSession(session),
                      ),
                    );
                  },
                ),
    );
  }
}

/// Screen showing detailed view of a saved session
class SessionDetailScreen extends StatefulWidget {
  final SessionMetadata session;

  const SessionDetailScreen({super.key, required this.session});

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  List<SensorData>? _sessionData;
  bool _isLoading = true;
  String _selectedMetric = 'co2';

  @override
  void initState() {
    super.initState();
    _loadSessionData();
  }

  Future<void> _loadSessionData() async {
    setState(() {
      _isLoading = true;
    });

    final sessionService = context.read<SessionService>();
    final data = await sessionService.loadSession(widget.session.filePath);

    setState(() {
      _sessionData = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM d, yyyy - HH:mm:ss');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Details'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _sessionData == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load session data',
                        style: theme.textTheme.titleLarge,
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Session metadata card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Session Information',
                                style: theme.textTheme.titleLarge,
                              ),
                              const Divider(),
                              _buildInfoRow('Started', dateFormat.format(widget.session.startTime)),
                              _buildInfoRow('Ended', dateFormat.format(widget.session.endTime)),
                              _buildInfoRow('Duration', widget.session.durationString),
                              _buildInfoRow('Data Points', '${widget.session.dataPoints}'),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Statistics card
                      if (_sessionData!.isNotEmpty) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Statistics',
                                  style: theme.textTheme.titleLarge,
                                ),
                                const Divider(),
                                ..._buildStatistics(_sessionData!),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Chart
                        TimeSeriesChart(
                          data: _sessionData!,
                          selectedMetric: _selectedMetric,
                          onMetricChanged: (metric) {
                            setState(() {
                              _selectedMetric = metric;
                            });
                          },
                        ),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStatistics(List<SensorData> data) {
    final co2Values = data.map((d) => d.co2).toList();
    final humidityValues = data.map((d) => d.humidity).toList();
    final temperatureValues = data.map((d) => d.temperature).toList();

    final co2Min = co2Values.reduce((a, b) => a < b ? a : b);
    final co2Max = co2Values.reduce((a, b) => a > b ? a : b);
    final co2Avg = co2Values.reduce((a, b) => a + b) / co2Values.length;

    final humidityMin = humidityValues.reduce((a, b) => a < b ? a : b);
    final humidityMax = humidityValues.reduce((a, b) => a > b ? a : b);
    final humidityAvg = humidityValues.reduce((a, b) => a + b) / humidityValues.length;

    final temperatureMin = temperatureValues.reduce((a, b) => a < b ? a : b);
    final temperatureMax = temperatureValues.reduce((a, b) => a > b ? a : b);
    final temperatureAvg = temperatureValues.reduce((a, b) => a + b) / temperatureValues.length;

    final maxAlert = data.map((d) => d.alert).reduce((a, b) => a > b ? a : b);

    return [
      const SizedBox(height: 8),
      Text('CO₂', style: const TextStyle(fontWeight: FontWeight.bold)),
      _buildInfoRow('Min', '${co2Min.toStringAsFixed(0)} ppm'),
      _buildInfoRow('Max', '${co2Max.toStringAsFixed(0)} ppm'),
      _buildInfoRow('Avg', '${co2Avg.toStringAsFixed(0)} ppm'),
      const SizedBox(height: 12),
      Text('Humidity', style: const TextStyle(fontWeight: FontWeight.bold)),
      _buildInfoRow('Min', '${humidityMin.toStringAsFixed(1)}%'),
      _buildInfoRow('Max', '${humidityMax.toStringAsFixed(1)}%'),
      _buildInfoRow('Avg', '${humidityAvg.toStringAsFixed(1)}%'),
      const SizedBox(height: 12),
      Text('Temperature', style: const TextStyle(fontWeight: FontWeight.bold)),
      _buildInfoRow('Min', '${temperatureMin.toStringAsFixed(1)}°C'),
      _buildInfoRow('Max', '${temperatureMax.toStringAsFixed(1)}°C'),
      _buildInfoRow('Avg', '${temperatureAvg.toStringAsFixed(1)}°C'),
      const SizedBox(height: 12),
      _buildInfoRow('Max Alert Level', '$maxAlert (${_getAlertName(maxAlert)})'),
    ];
  }

  String _getAlertName(int alert) {
    switch (alert) {
      case 0:
        return 'Normal';
      case 1:
        return 'Low';
      case 2:
        return 'Medium';
      case 3:
        return 'High';
      default:
        return 'Unknown';
    }
  }
}
