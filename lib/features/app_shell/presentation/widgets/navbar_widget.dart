import 'package:flutter/material.dart';
import 'package:nexshift_app/core/data/datasources/notifiers.dart';
import 'package:nexshift_app/core/data/models/user_model.dart';
import 'package:nexshift_app/core/presentation/widgets/value_listenable_builder_widget.dart';

class NavbarWidget extends StatelessWidget {
  const NavbarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder2<int, User?>(
      first: selectedPageNotifier,
      second: userNotifier,
      builder: (context, selectedPage, user, child) {
        return NavigationBarTheme(
          data: NavigationBarThemeData(
            labelTextStyle: WidgetStateTextStyle.resolveWith((
              Set<WidgetState> states,
            ) {
              final Color color = states.contains(WidgetState.selected)
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.tertiary;
              return TextStyle(color: color, fontSize: 14);
            }),
          ),
          child: NavigationBar(
            height: 70.0,
            destinations: [
              NavigationDestination(
                icon: Icon(
                  user == null
                      ? Icons
                            .person // icône par défaut
                      : user.status == "leader"
                      ? Icons.groups
                      : user.status == "chief"
                      ? Icons.group
                      : Icons.person,
                ),
                label: 'Astreintes',
              ),
              NavigationDestination(
                icon: Icon(Icons.calendar_month),
                label: 'Planning',
              ),
            ],
            onDestinationSelected: (int value) {
              selectedPageNotifier.value = value;
            },
            selectedIndex: selectedPage,
          ),
        );
      },
    );
  }
}
