import 'package:flutter/material.dart';

class HomeBottomPanel extends StatelessWidget {
  const HomeBottomPanel({
    super.key,
  });

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
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceEvenly,
              children: const [

                _BottomButton(
                  icon: Icons.home_rounded,
                  label: "Ana Sayfa",
                ),

                _BottomButton(
                  icon: Icons.history_rounded,
                  label: "Geçmiş",
                ),

                _BottomButton(
                  icon: Icons.favorite_rounded,
                  label: "Favoriler",
                ),

                _BottomButton(
                  icon: Icons.person_rounded,
                  label: "Profil",
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

  const _BottomButton({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () {
        debugPrint(label);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            Icon(
              icon,
              size: 24,
            ),

            const SizedBox(height: 4),

            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}