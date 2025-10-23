import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/ble_service.dart';
import '../services/session_service.dart';

/// Settings screen for device control and session options
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _lastCommandResult;
  DateTime? _lastCommandTime;
  bool _isCommandInProgress = false;

  /// Send a control command to the device
  Future<void> _sendCommand(Future<bool> Function() commandFn, String description) async {
    if (_isCommandInProgress) return;
    
    setState(() {
      _isCommandInProgress = true;
      _lastCommandResult = null;
    });

    try {
      final success = await commandFn();

      setState(() {
        _lastCommandResult = success 
            ? '$description command sent successfully'
            : '$description command failed';
        _lastCommandTime = DateTime.now();
        _isCommandInProgress = false;
      });

      // Show snackbar feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_lastCommandResult!),
            backgroundColor: success ? Colors.green : Colors.red,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _lastCommandResult = 'Error: $e';
        _lastCommandTime = DateTime.now();
        _isCommandInProgress = false;
      });
    }
  }

  /// Show confirmation dialog for sleep command
  void _showSleepConfirmDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.nightlight_round, color: Colors.blue),
              SizedBox(width: 8),
              Text('Force Deep Sleep'),
            ],
          ),
          content: const Text(
            'This will put the device into deep sleep mode. '
            'You will need to press the button on the device to wake it up.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                final bleService = context.read<BleService>();
                _sendCommand(
                  () => bleService.sendSleepCommand(),
                  'Force Sleep',
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blue,
              ),
              child: const Text('Put to Sleep'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bleService = context.watch<BleService>();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings & Controls'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Device Controls Section
            Text(
              'Device Controls',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            
            // Mute/Unmute toggle
            Card(
              child: ListTile(
                leading: Icon(
                  bleService.isMuted ? Icons.volume_off : Icons.volume_up,
                  color: bleService.isMuted 
                      ? theme.colorScheme.error 
                      : theme.colorScheme.primary,
                ),
                title: Text(bleService.isMuted ? 'Device is Muted' : 'Device is Active'),
                subtitle: Text(
                  bleService.isMuted 
                      ? 'Buzzer alerts are disabled'
                      : 'Buzzer alerts are enabled'
                ),
                trailing: Switch(
                  value: bleService.isMuted,
                  onChanged: _isCommandInProgress ? null : (value) {
                    if (value) {
                      _sendCommand(
                        () => bleService.sendMuteCommand(),
                        'Mute',
                      );
                    } else {
                      _sendCommand(
                        () => bleService.sendUnmuteCommand(),
                        'Unmute',
                      );
                    }
                  },
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Request Data button
            Card(
              child: ListTile(
                leading: const Icon(Icons.refresh, color: Colors.blue),
                title: const Text('Request Immediate Data'),
                subtitle: const Text('Request an immediate sensor reading'),
                onTap: _isCommandInProgress ? null : () {
                  _sendCommand(
                    () => bleService.sendRequestDataCommand(),
                    'Request Data',
                  );
                },
                trailing: _isCommandInProgress
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.chevron_right),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Reset alerts button
            Card(
              child: ListTile(
                leading: const Icon(Icons.notification_important, color: Colors.orange),
                title: const Text('Reset Alerts & Unmute'),
                subtitle: const Text('Clear all alerts and unmute the device'),
                onTap: _isCommandInProgress ? null : () {
                  _sendCommand(
                    () => bleService.sendResetCommand(),
                    'Reset',
                  );
                },
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Force sleep button
            Card(
              child: ListTile(
                leading: const Icon(Icons.nightlight_round, color: Colors.blue),
                title: const Text('Force Deep Sleep'),
                subtitle: const Text('Put device into low-power mode'),
                onTap: _isCommandInProgress ? null : _showSleepConfirmDialog,
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Session Options Section
            Text(
              'Session Options',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            
            // Save session toggle
            Consumer<SessionService>(
              builder: (context, sessionService, child) => Card(
                child: SwitchListTile(
                  title: const Text('Save Current Session'),
                  subtitle: Text(
                    sessionService.saveCurrentSession
                        ? 'Session will be saved when you disconnect'
                        : 'Session will be discarded when you disconnect'
                  ),
                  value: sessionService.saveCurrentSession,
                  onChanged: (value) {
                    context.read<SessionService>().setSaveSession(value);
                  },
                  secondary: Icon(
                    sessionService.saveCurrentSession 
                        ? Icons.save 
                        : Icons.delete_outline,
                    color: sessionService.saveCurrentSession
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Session statistics
            Consumer<SessionService>(
              builder: (context, sessionService, child) {
                if (sessionService.currentSessionDataCount == 0) {
                  return const SizedBox.shrink();
                }
                
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Current Session Statistics',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        _buildStatRow('Data Points', '${sessionService.currentSessionDataCount}'),
                        if (sessionService.sessionStartTime != null)
                          _buildStatRow(
                            'Duration',
                            _formatDuration(DateTime.now().difference(sessionService.sessionStartTime!)),
                          ),
                        const Divider(),
                        if (sessionService.getSessionStatistics() != null)
                          ..._buildDetailedStats(sessionService.getSessionStatistics()!),
                      ],
                    ),
                  ),
                );
              },
            ),
            
            const SizedBox(height: 24),
            
            // Command status
            if (_lastCommandResult != null)
              Card(
                color: _lastCommandResult!.contains('successfully')
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _lastCommandResult!.contains('successfully')
                                ? Icons.check_circle
                                : Icons.error,
                            color: _lastCommandResult!.contains('successfully')
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Last Command',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: _lastCommandResult!.contains('successfully')
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _lastCommandResult!,
                        style: TextStyle(
                          color: _lastCommandResult!.contains('successfully')
                              ? theme.colorScheme.onPrimaryContainer
                              : theme.colorScheme.onErrorContainer,
                        ),
                      ),
                      if (_lastCommandTime != null)
                        Text(
                          'At ${_lastCommandTime!.hour.toString().padLeft(2, '0')}:'
                          '${_lastCommandTime!.minute.toString().padLeft(2, '0')}:'
                          '${_lastCommandTime!.second.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 12,
                            color: (_lastCommandResult!.contains('successfully')
                                ? theme.colorScheme.onPrimaryContainer
                                : theme.colorScheme.onErrorContainer)
                                .withValues(alpha: 0.7),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            
            const SizedBox(height: 16),
            
            // Command in progress indicator
            if (_isCommandInProgress)
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Sending command...'),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
  
  List<Widget> _buildDetailedStats(SessionStatistics stats) {
    return [
      Text('CO₂', style: const TextStyle(fontWeight: FontWeight.bold)),
      _buildStatRow('Min', '${stats.co2Min.toStringAsFixed(0)} ppm'),
      _buildStatRow('Max', '${stats.co2Max.toStringAsFixed(0)} ppm'),
      _buildStatRow('Avg', '${stats.co2Avg.toStringAsFixed(0)} ppm'),
      const SizedBox(height: 8),
      Text('Humidity', style: const TextStyle(fontWeight: FontWeight.bold)),
      _buildStatRow('Min', '${stats.humidityMin.toStringAsFixed(1)}%'),
      _buildStatRow('Max', '${stats.humidityMax.toStringAsFixed(1)}%'),
      _buildStatRow('Avg', '${stats.humidityAvg.toStringAsFixed(1)}%'),
      const SizedBox(height: 8),
      Text('Temperature', style: const TextStyle(fontWeight: FontWeight.bold)),
      _buildStatRow('Min', '${stats.temperatureMin.toStringAsFixed(1)}°C'),
      _buildStatRow('Max', '${stats.temperatureMax.toStringAsFixed(1)}°C'),
      _buildStatRow('Avg', '${stats.temperatureAvg.toStringAsFixed(1)}°C'),
    ];
  }
  
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (hours > 0) {
      return '${hours}h ${minutes}m ${seconds}s';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
}
