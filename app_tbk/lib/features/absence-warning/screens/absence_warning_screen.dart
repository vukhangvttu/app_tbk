import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import '../widgets/absence_warning_card.dart';

class AbsenceWarningScreen extends StatelessWidget {
  const AbsenceWarningScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'absence_warning.title'.tr(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: const AbsenceWarningCard(),
      ),
    );
  }
}
