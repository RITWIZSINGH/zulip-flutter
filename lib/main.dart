import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart';

import 'api/model/model.dart';
import 'api/route/messages.dart';
import 'store.dart';

void main() {
  runApp(const ZulipApp());
}

class ZulipApp extends StatelessWidget {
  const ZulipApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Just one account for now.
    return const PerAccountRoot();
  }
}

class PerAccountRoot extends StatefulWidget {
  const PerAccountRoot({super.key});

  @override
  State<PerAccountRoot> createState() => _PerAccountRootState();
}

class _PerAccountRootState extends State<PerAccountRoot> {
  PerAccountStore? store;

  @override
  void initState() {
    super.initState();
    (() async {
      final store = await PerAccountStore.load();
      setState(() {
        this.store = store;
      });
    })();
  }

  @override
  Widget build(BuildContext context) {
    if (store == null) return const LoadingPage();
    return PerAccountStoreWidget(
        store: store!,
        child: MaterialApp(
          title: 'Zulip',
          theme: ThemeData(primarySwatch: Colors.blue), // TODO Zulip purple
          home: const HomePage(),
        ));
  }
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class PerAccountStoreWidget extends InheritedNotifier<PerAccountStore> {
  const PerAccountStoreWidget(
      {super.key, required PerAccountStore store, required super.child})
      : super(notifier: store);

  PerAccountStore get store => notifier!;

  static PerAccountStore of(BuildContext context) {
    final widget =
        context.dependOnInheritedWidgetOfExactType<PerAccountStoreWidget>();
    assert(widget != null, 'No PerAccountStoreWidget ancestor');
    return widget!.store;
  }

  @override
  bool updateShouldNotify(covariant PerAccountStoreWidget oldWidget) =>
      store != oldWidget.store;
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final store = PerAccountStoreWidget.of(context);
    return Scaffold(
        appBar: AppBar(title: const Text("Home")),
        body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('🚧 Under construction 🚧'),
          const SizedBox(height: 8),
          Text('Connected to: ${store.account.realmUrl}'),
          Text('Zulip server version: ${store.initialSnapshot.zulip_version}'),
          Text(
              'Subscribed to ${store.initialSnapshot.subscriptions.length} streams'),
          const SizedBox(height: 16),
          ElevatedButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const MessageListPage())),
              child: const Text("All messages"))
        ])));
  }
}

class MessageListPage extends StatefulWidget {
  const MessageListPage({Key? key}) : super(key: key);

  @override
  State<MessageListPage> createState() => _MessageListPageState();
}

class _MessageListPageState extends State<MessageListPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(title: const Text("Some messages")),
        body: Center(
            child: Column(children: const [
          Expanded(child: MessageList()),
          SizedBox(
              height: 80,
              child: Center(child: Text("(Compose box goes here.)"))),
        ])));
  }
}

class MessageList extends StatefulWidget {
  const MessageList({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final List<Message> messages = []; // TODO move state up to store
  bool fetched = false; // TODO this will get more complex

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetch();
  }

  Future<void> _fetch() async {
    final store = PerAccountStoreWidget.of(context);
    final result =
        await getMessages(store.connection, num_before: 10, num_after: 10);
    setState(() {
      messages.addAll(result.messages);
      fetched = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!fetched) return const Center(child: CircularProgressIndicator());
    return ListView.separated(
        itemCount: messages.length,
        separatorBuilder: (context, i) => const SizedBox(height: 16),
        itemBuilder: (context, i) => MessageItem(message: messages[i]));
  }
}

class MessageItem extends StatelessWidget {
  const MessageItem({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // TODO recipient headings
          SenderHeading(message: message),
          MessageContent(message: message),
        ]));
  }
}

class SenderHeading extends StatelessWidget {
  const SenderHeading({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        height: 48,
        child: Row(children: [
          // TODO avatar
          Expanded(
              child: Text(message.sender_full_name,
                  style: const TextStyle(fontWeight: FontWeight.bold))),
          Text("${message.timestamp}"), // TODO better format time
        ]));
  }
}

class MessageContent extends StatelessWidget {
  const MessageContent({super.key, required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final fragment =
        HtmlParser(message.content, parseMeta: false).parseFragment();
    final nodes = fragment.nodes.where(_acceptNode);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...nodes.map(_buildDirectChildNode),
    ]);
  }

  static bool _acceptNode(dom.Node node) {
    if (node is dom.Element) return true;
    // We get a bunch of newline Text nodes between paragraphs.
    // A browser seems to ignore these; let's do the same.
    if (node is dom.Text && (node.text == "\n")) return false;
    // Does any other kind of node occur?  Well, we'd see it below.
    return true;
  }

  Widget _buildDirectChildNode(dom.Node node) {
    switch (node.nodeType) {
      case dom.Node.ELEMENT_NODE:
        return _buildDirectChildElement(node as dom.Element);
      case dom.Node.TEXT_NODE:
        final text = (node as dom.Text).text;
        return _errorText("text: «$text»"); // TODO can this happen?
      default:
        return _errorText(
            "(node of type ${node.nodeType})"); // TODO can this happen?
    }
  }

  Widget _buildDirectChildElement(dom.Element element) {
    switch (element.localName) {
      case 'p':
        return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child:
                Text.rich(TextSpan(children: _buildInlineList(element.nodes))));
      default:
        // TODO handle more types of elements
        return Text.rich(_errorUnimplemented(element));
    }
  }

  List<InlineSpan> _buildInlineList(dom.NodeList nodes) =>
      List.of(nodes.map(_buildInlineNode));

  InlineSpan _buildInlineNode(dom.Node node) {
    if (node is dom.Text) return TextSpan(text: node.text);
    if (node is! dom.Element) {
      return TextSpan(
          text: "(unimplemented dom.Node type: ${node.nodeType})",
          style: errorStyle);
    }
    switch (node.localName) {
      default:
        return _errorUnimplemented(node);
    }
  }

  Widget _errorText(String text) => Text(text, style: errorStyle);

  InlineSpan _errorUnimplemented(dom.Element element) => TextSpan(children: [
        const TextSpan(text: "(unimplemented:", style: errorStyle),
        TextSpan(text: element.outerHtml, style: errorCodeStyle),
        const TextSpan(text: ")", style: errorStyle),
      ]);

  static const errorStyle =
      TextStyle(fontWeight: FontWeight.bold, color: Colors.red);

  static const errorCodeStyle =
      TextStyle(color: Colors.red, fontFamily: 'monospace');
}
