import 'package:flutter/material.dart';

class HomeBottomPanel extends StatelessWidget {
  const HomeBottomPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(28),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 18,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              const SizedBox(height: 22),

              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Nereye gitmek istiyorsunuz?",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Container(
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xffF4F5F7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  children: [
                    SizedBox(width: 16),
                    Icon(Icons.search),
                    SizedBox(width: 12),
                    Text(
                      "Adres ara",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              Row(
                children: [
                  Expanded(
                    child: _QuickButton(
                      icon: Icons.home_rounded,
                      title: "Ev",
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickButton(
                      icon: Icons.work_rounded,
                      title: "İş",
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickButton(
                      icon: Icons.star_rounded,
                      title: "Favoriler",
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  final IconData icon;
  final String title;

  const _QuickButton({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {},
      child: Ink(
        height: 84,
        decoration: BoxDecoration(
          color: const Color(0xffFFF9E6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xffF3D04F),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: Colors.black87,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}