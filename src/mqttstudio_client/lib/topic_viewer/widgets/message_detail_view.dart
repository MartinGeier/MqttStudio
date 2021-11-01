import 'package:flutter/material.dart';
import 'package:mqttstudio/topic_viewer/topic_viewer_viewmodel.dart';
import 'package:provider/provider.dart';

class MessageDetailView extends StatelessWidget {
  const MessageDetailView({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<TopicViewerViewmodel>(builder: (context, viewmodel, child) {
      return Container(child: Text(viewmodel.selectedMessage?.topicName ?? ''));
    });
  }
}
