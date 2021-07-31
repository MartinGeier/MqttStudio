import 'package:flutter/material.dart';

class FormRow extends StatelessWidget {
  final List<Widget> children;

  const FormRow({Key? key, required this.children}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: Row(
        // mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
