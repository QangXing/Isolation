// 应用 UI 冒烟测试：验证主界面底部导航栏渲染与切换。
// 仅测试纯 Widget（不涉及 MethodChannel / 平台插件），保证 CI 中可稳定运行。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isolation/widgets/bottom_nav_bar.dart';

void main() {
  testWidgets('BottomNavBar renders three tabs', (WidgetTester tester) async {
    var tapped = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox.shrink(),
          bottomNavigationBar: BottomNavBar(
            currentIndex: 0,
            onTap: (index) => tapped = index,
          ),
        ),
      ),
    );

    expect(find.text('主页'), findsOneWidget);
    expect(find.text('管理'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);

    await tester.tap(find.text('管理'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });
}
