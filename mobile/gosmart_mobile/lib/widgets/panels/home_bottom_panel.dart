import 'package:flutter/material.dart';

class HomeBottomPanel extends StatelessWidget {
  final VoidCallback? onDriverTap;
  final VoidCallback? onProfileTap;

  const HomeBottomPanel({super.key, this.onDriverTap, this.onProfileTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 20,
      child: SafeArea(
        child: Material(
          elevation: 12,
          borderRadius: BorderRadius.circular(22),
          color: Colors.white,
          child: Container(
            height: 68,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                const _BottomButton(
                  icon: Icons.home_rounded,
                  label: "Ana Sayfa",
                ),

                const _BottomButton(
                  icon: Icons.history_rounded,
                  label: "Geçmiş",
                ),

                _BottomButton(
                  icon: Icons.local_taxi_rounded,
                  label: "Sürücü",
                  onTap: onDriverTap,
                ),

                _BottomButton(
                  icon: Icons.person_rounded,
                  label: "Profil",
                  onTap: onProfileTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _BottomButton({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap ?? () => debugPrint(label),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24),

            const SizedBox(height: 4),

            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
