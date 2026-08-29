// lib/features/main_shell.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const _primaryPurple = Color(0xFF5C4DFF);

class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _tabs = [
    '/dashboard',
    '/activity',
    '/goals',
    '/recommendation',
    '/profile',
  ];

  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    for (int i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i])) return i;
    }
    // Layar seperti /focus-session, /reminders, /settings, dll
    // bukan bagian dari salah satu dari 5 tab utama — jangan paksa
    // highlight ke salah satu tab (sebelumnya selalu jatuh ke Beranda,
    // padahal tidak selalu relevan/benar).
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final idx   = _currentIndex(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: child,
      bottomNavigationBar: _AppBottomNavBar(
        currentIndex: idx,
        isDark: isDark,
        onTap: (i) {
          if (i != idx) context.go(_tabs[i]);
        },
      ),
    );
  }
}

class _AppBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final bool isDark;
  final ValueChanged<int> onTap;
  const _AppBottomNavBar({
    required this.currentIndex,
    required this.isDark,
    required this.onTap,
  });

  static const _items = [
    _NavItem(icon: Icons.grid_view_rounded,       label: 'Beranda'),
    _NavItem(icon: Icons.check_circle_outline,    label: 'Aktivitas'),
    _NavItem(icon: Icons.track_changes_outlined,  label: 'Goal'),
    _NavItem(icon: Icons.menu_book_outlined,      label: 'Rekomendasi'),
    _NavItem(icon: Icons.person_outline_rounded,  label: 'Profil'),
  ];

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF1A1A2E) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: List.generate(_items.length, (i) {
              final isActive = i == currentIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(i),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive
                              ? _primaryPurple.withOpacity(0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          _items[i].icon,
                          size: 22,
                          color: isActive
                              ? _primaryPurple
                              : isDark
                                  ? Colors.white38
                                  : Colors.grey[400],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _items[i].label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: isActive
                              ? _primaryPurple
                              : isDark
                                  ? Colors.white38
                                  : Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
