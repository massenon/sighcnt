import 'package:flutter/material.dart';

void main() => runApp(const SighMobile());

class SighMobile extends StatelessWidget {
  const SighMobile({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'SIGH-CNT',
      debugShowCheckedModeBanner: false,
      home: Scaffold(body: Center(child: Text('SIGH-CNT — mobile'))),
    );
  }
}
