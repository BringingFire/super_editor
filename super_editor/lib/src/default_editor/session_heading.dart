import 'package:attributed_text/attributed_text.dart';
import 'package:super_editor/src/default_editor/attributions.dart';
import 'package:super_editor/src/default_editor/paragraph.dart';

class SessionHeadingNode extends ParagraphNode {
  SessionHeadingNode({
    required String id,
    required this.number,
    required this.createdAt,
    required this.title,
    Map<String, dynamic>? metadata,
  }) : super(
          id: id,
          text: AttributedText(),
          metadata: metadata,
        ) {
    if (getMetadataValue("blockType") == null) {
      putMetadataValue("blockType", sessionHeaderAttribution);
    }
  }

  final int number;
  final DateTime createdAt;
  final String? title;
}
