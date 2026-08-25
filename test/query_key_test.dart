import 'package:queryx/queryx.dart';
import 'package:test/test.dart';

void main() {
  group('QueryKey', () {
    test('equal parts produce equal keys', () {
      final a = QueryKey(['user', 1]);
      final b = QueryKey(['user', 1]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('map argument order does not affect identity', () {
      final a = QueryKey([
        'orders',
        {'status': 'pending', 'page': 1}
      ]);
      final b = QueryKey([
        'orders',
        {'page': 1, 'status': 'pending'}
      ]);
      expect(a, equals(b));
    });

    test('different values produce different keys', () {
      final a = QueryKey(['user', 1]);
      final b = QueryKey(['user', 2]);
      expect(a, isNot(equals(b)));
    });

    test('isPrefixedBy matches hierarchical keys', () {
      final usersList = QueryKey(['users']);
      final singleUser = QueryKey(['users', 1]);
      expect(singleUser.isPrefixedBy(usersList), isTrue);
      expect(usersList.isPrefixedBy(singleUser), isFalse);
    });
  });
}
