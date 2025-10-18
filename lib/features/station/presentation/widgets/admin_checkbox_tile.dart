import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/user_storage_helper.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/repositories/user_repository.dart';

class AdminCheckboxTile extends StatefulWidget {
  final User user;
  final ScaffoldMessengerState scaffoldMessenger;
  final Future<void> Function() loadData;
  final User? currentUser;

  AdminCheckboxTile({
    required this.user,
    required this.scaffoldMessenger,
    required this.loadData,
    required this.currentUser,
  });

  @override
  State<AdminCheckboxTile> createState() => _AdminCheckboxTileState();
}

class _AdminCheckboxTileState extends State<AdminCheckboxTile> {
  late bool isAdmin;

  @override
  void initState() {
    super.initState();
    isAdmin = widget.user.admin;
  }

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: isAdmin,
      onChanged: (val) async {
        setState(() => isAdmin = val ?? false);
        final updated = User(
          id: widget.user.id,
          firstName: widget.user.firstName,
          lastName: widget.user.lastName,
          station: widget.user.station,
          status: widget.user.status,
          team: widget.user.team,
          skills: widget.user.skills,
          admin: val ?? false,
        );
        final repo = UserRepository();
        await repo.upsert(updated);
        if (widget.currentUser?.id == widget.user.id) {
          await UserStorageHelper.saveUser(updated);
        }
        await widget.loadData();
        widget.scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(
              val == true ? 'Rôle admin activé' : 'Rôle admin désactivé',
            ),
          ),
        );
      },
      title: Row(
        children: [
          Icon(Icons.settings, color: Colors.teal),
          const SizedBox(width: 8),
          const Text('Admin', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      subtitle: const Text('Accès privilégié, bypass des restrictions'),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}
