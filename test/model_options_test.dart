import 'package:flutter_test/flutter_test.dart';
import 'package:typeflux_app/chat/model_options.dart';

void main() {
  test('catalog capabilities choose ordered supported reasoning levels', () {
    final model = ModelOption.fromJson({
      'id': 'deep',
      'name': 'Deep model',
      'capabilities': {'reasoning': true},
      'reasoning_efforts': ['max', 'low', 'unknown', 'low', 'high'],
    });
    expect(model.reference, 'cloud:deep');
    expect(model.reasoningEfforts, ['low', 'high', 'max']);
    expect(model.isHighestEffort('max'), true);
    expect(model.isHighestEffort('high'), false);
    expect(model.isHighestEffort(''), false);
    expect(
      ModelOption.fromJson({
        'capabilities': {'reasoning': true},
      }).reasoningEfforts,
      ['low', 'medium', 'high'],
    );
    expect(
      ModelOption.fromJson({
        'reasoning_efforts': ['high'],
      }).reasoningEfforts,
      isEmpty,
    );
  });

  test('nearest effort preserves automatic and chooses lighter on ties', () {
    expect(nearestReasoningEffort('', ['low', 'high']), '');
    expect(nearestReasoningEffort('auto', ['low', 'high']), '');
    expect(nearestReasoningEffort('max', []), '');
    expect(nearestReasoningEffort('invalid', ['high']), '');
    expect(nearestReasoningEffort('medium', ['high', 'low']), 'low');
    expect(nearestReasoningEffort('max', ['low', 'high']), 'high');
    expect(nearestReasoningEffort('high', ['low', 'high', 'max']), 'high');
  });

  test('only actual validated catalog metadata is exposed', () {
    final complete = ModelOption.fromJson({
      'id': 'default',
      'vision': false,
      'context_window_tokens': 200000,
      'max_output_tokens': 64000,
      'pricing': {'multiplier': '1.5000'},
    });
    expect(complete.isDefault, true);
    expect(complete.vision, false);
    expect(complete.contextWindowTokens, 200000);
    expect(complete.maxOutputTokens, 64000);
    expect(complete.multiplierLabel, '1.5X');
    final missing = ModelOption.fromJson({'id': 'other'});
    expect(missing.vision, isNull);
    expect(missing.contextWindowTokens, isNull);
    expect(missing.multiplierLabel, isNull);
    for (final invalid in ['-1', '0', '101', 'NaN', '1.00001', '1 X']) {
      expect(
        ModelOption.fromJson({
          'pricing': {'multiplier': invalid},
        }).multiplierLabel,
        isNull,
      );
    }
  });
}
