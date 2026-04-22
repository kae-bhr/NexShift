import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nexshift_app/core/utils/constants.dart';

/// Page affichée quand le build courant est trop ancien et doit être mis à jour.
class UpdateRequiredPage extends StatelessWidget {
  final String message;
  final String storeUrl;

  const UpdateRequiredPage({
    super.key,
    required this.message,
    required this.storeUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.system_update, size: 120, color: KColors.appNameColor),
              const SizedBox(height: 32),
              Text(
                'Mise à jour requise',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              if (storeUrl.isNotEmpty) ...[
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(storeUrl);
                    if (uri != null && await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Mettre à jour'),
                  style: FilledButton.styleFrom(
                    backgroundColor: KColors.appNameColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
