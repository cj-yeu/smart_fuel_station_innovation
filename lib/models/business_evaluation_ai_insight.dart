enum BusinessEvaluationAiInsightCacheStatus { generated, cached }

enum BusinessEvaluationAiDriverType { strength, risk }

enum BusinessEvaluationAiActionPriority { high, medium, low }

enum BusinessEvaluationAiScenarioVariable {
  dailyCustomers,
  averageLitres,
  fuelMargin,
  fixedOperatingCost,
  initialInvestment,
}

enum BusinessEvaluationAiScenarioDirection { increase, decrease, review }

class BusinessEvaluationAiInsightDriver {
  final BusinessEvaluationAiDriverType type;
  final String factor;
  final String evidence;

  const BusinessEvaluationAiInsightDriver({
    required this.type,
    required this.factor,
    required this.evidence,
  });
}

class BusinessEvaluationAiInsightAction {
  final BusinessEvaluationAiActionPriority priority;
  final String action;
  final String reason;

  const BusinessEvaluationAiInsightAction({
    required this.priority,
    required this.action,
    required this.reason,
  });
}

class BusinessEvaluationAiInsightScenario {
  final BusinessEvaluationAiScenarioVariable variable;
  final BusinessEvaluationAiScenarioDirection direction;
  final String reason;

  const BusinessEvaluationAiInsightScenario({
    required this.variable,
    required this.direction,
    required this.reason,
  });
}

class BusinessEvaluationAiInsight {
  static const modelName = 'gpt-5.6-sol';

  final BusinessEvaluationAiInsightCacheStatus cacheStatus;
  final String executiveSummary;
  final List<BusinessEvaluationAiInsightDriver> drivers;
  final List<BusinessEvaluationAiInsightAction> actions;
  final BusinessEvaluationAiInsightScenario scenarioToTest;
  final List<String> dataLimitations;
  final String disclaimer;
  final String model;
  final String promptVersion;
  final DateTime generatedAt;
  final DateTime sourceEvaluationUpdatedAt;

  const BusinessEvaluationAiInsight({
    required this.cacheStatus,
    required this.executiveSummary,
    required this.drivers,
    required this.actions,
    required this.scenarioToTest,
    required this.dataLimitations,
    required this.disclaimer,
    required this.model,
    required this.promptVersion,
    required this.generatedAt,
    required this.sourceEvaluationUpdatedAt,
  });

  bool isStaleFor(DateTime evaluationUpdatedAt) =>
      sourceEvaluationUpdatedAt.isBefore(evaluationUpdatedAt);

  factory BusinessEvaluationAiInsight.fromFunctionResponse(Object? value) {
    final response = _exactMap(value, const [
      'cache_status',
      'insight',
      'model',
      'prompt_version',
      'generated_at',
      'source_evaluation_updated_at',
    ]);
    final status = switch (response['cache_status']) {
      'generated' => BusinessEvaluationAiInsightCacheStatus.generated,
      'cached' => BusinessEvaluationAiInsightCacheStatus.cached,
      _ => throw const FormatException('AI insight response is invalid.'),
    };

    return _fromParts(
      cacheStatus: status,
      insight: response['insight'],
      model: response['model'],
      promptVersion: response['prompt_version'],
      generatedAt: response['generated_at'],
      sourceEvaluationUpdatedAt: response['source_evaluation_updated_at'],
    );
  }

  factory BusinessEvaluationAiInsight.fromStoredRow(Object? value) {
    final row = _exactMap(value, const [
      'evaluation_id',
      'insight',
      'model',
      'prompt_version',
      'input_hash',
      'source_evaluation_updated_at',
      'generated_at',
    ]);
    _uuid(row['evaluation_id']);
    final inputHash = row['input_hash'];
    if (inputHash is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(inputHash)) {
      throw const FormatException('Stored AI insight is invalid.');
    }

    return _fromParts(
      cacheStatus: BusinessEvaluationAiInsightCacheStatus.cached,
      insight: row['insight'],
      model: row['model'],
      promptVersion: row['prompt_version'],
      generatedAt: row['generated_at'],
      sourceEvaluationUpdatedAt: row['source_evaluation_updated_at'],
    );
  }

  static BusinessEvaluationAiInsight _fromParts({
    required BusinessEvaluationAiInsightCacheStatus cacheStatus,
    required Object? insight,
    required Object? model,
    required Object? promptVersion,
    required Object? generatedAt,
    required Object? sourceEvaluationUpdatedAt,
  }) {
    if (model != modelName) {
      throw const FormatException('AI insight model is invalid.');
    }
    if (promptVersion is! String ||
        !RegExp(r'^[A-Za-z0-9._-]{1,80}$').hasMatch(promptVersion)) {
      throw const FormatException('AI insight prompt version is invalid.');
    }

    final parsedInsight = _parseInsight(insight);
    return BusinessEvaluationAiInsight(
      cacheStatus: cacheStatus,
      executiveSummary: parsedInsight.executiveSummary,
      drivers: List.unmodifiable(parsedInsight.drivers),
      actions: List.unmodifiable(parsedInsight.actions),
      scenarioToTest: parsedInsight.scenarioToTest,
      dataLimitations: List.unmodifiable(parsedInsight.dataLimitations),
      disclaimer: parsedInsight.disclaimer,
      model: modelName,
      promptVersion: promptVersion,
      generatedAt: _timestamp(generatedAt),
      sourceEvaluationUpdatedAt: _timestamp(sourceEvaluationUpdatedAt),
    );
  }

  static _InsightContent _parseInsight(Object? value) {
    final insight = _exactMap(value, const [
      'executive_summary',
      'drivers',
      'actions',
      'scenario_to_test',
      'data_limitations',
      'disclaimer',
    ]);
    final driverValues = _boundedList(insight['drivers'], 1, 6);
    final actionValues = _boundedList(insight['actions'], 3, 3);
    final limitationValues = _boundedList(insight['data_limitations'], 0, 6);

    return _InsightContent(
      executiveSummary: _string(insight['executive_summary'], 1000),
      drivers: driverValues.map(_driver).toList(growable: false),
      actions: actionValues.map(_action).toList(growable: false),
      scenarioToTest: _scenario(insight['scenario_to_test']),
      dataLimitations: limitationValues
          .map((value) => _string(value, 240))
          .toList(growable: false),
      disclaimer: _string(insight['disclaimer'], 500),
    );
  }

  static BusinessEvaluationAiInsightDriver _driver(Object? value) {
    final driver = _exactMap(value, const ['type', 'factor', 'evidence']);
    final type = switch (driver['type']) {
      'strength' => BusinessEvaluationAiDriverType.strength,
      'risk' => BusinessEvaluationAiDriverType.risk,
      _ => throw const FormatException('AI insight driver is invalid.'),
    };
    return BusinessEvaluationAiInsightDriver(
      type: type,
      factor: _string(driver['factor'], 240),
      evidence: _string(driver['evidence'], 360),
    );
  }

  static BusinessEvaluationAiInsightAction _action(Object? value) {
    final action = _exactMap(value, const ['priority', 'action', 'reason']);
    final priority = switch (action['priority']) {
      'high' => BusinessEvaluationAiActionPriority.high,
      'medium' => BusinessEvaluationAiActionPriority.medium,
      'low' => BusinessEvaluationAiActionPriority.low,
      _ => throw const FormatException('AI insight action is invalid.'),
    };
    return BusinessEvaluationAiInsightAction(
      priority: priority,
      action: _string(action['action'], 240),
      reason: _string(action['reason'], 360),
    );
  }

  static BusinessEvaluationAiInsightScenario _scenario(Object? value) {
    final scenario = _exactMap(value, const [
      'variable',
      'direction',
      'reason',
    ]);
    final variable = switch (scenario['variable']) {
      'daily_customers' => BusinessEvaluationAiScenarioVariable.dailyCustomers,
      'average_litres' => BusinessEvaluationAiScenarioVariable.averageLitres,
      'fuel_margin' => BusinessEvaluationAiScenarioVariable.fuelMargin,
      'fixed_operating_cost' =>
        BusinessEvaluationAiScenarioVariable.fixedOperatingCost,
      'initial_investment' =>
        BusinessEvaluationAiScenarioVariable.initialInvestment,
      _ => throw const FormatException('AI insight scenario is invalid.'),
    };
    final direction = switch (scenario['direction']) {
      'increase' => BusinessEvaluationAiScenarioDirection.increase,
      'decrease' => BusinessEvaluationAiScenarioDirection.decrease,
      'review' => BusinessEvaluationAiScenarioDirection.review,
      _ => throw const FormatException('AI insight scenario is invalid.'),
    };
    return BusinessEvaluationAiInsightScenario(
      variable: variable,
      direction: direction,
      reason: _string(scenario['reason'], 360),
    );
  }

  static Map<String, dynamic> _exactMap(Object? value, List<String> keys) {
    if (value is! Map) {
      throw const FormatException('AI insight response is invalid.');
    }
    final map = Map<String, dynamic>.from(value);
    final actualKeys = map.keys.toSet();
    if (actualKeys.length != keys.length || !actualKeys.containsAll(keys)) {
      throw const FormatException('AI insight response is invalid.');
    }
    return map;
  }

  static List<dynamic> _boundedList(Object? value, int minimum, int maximum) {
    if (value is! List || value.length < minimum || value.length > maximum) {
      throw const FormatException('AI insight response is invalid.');
    }
    return value;
  }

  static String _string(Object? value, int maximumLength) {
    if (value is! String ||
        value.trim().isEmpty ||
        value.length > maximumLength) {
      throw const FormatException('AI insight response is invalid.');
    }
    return value;
  }

  static DateTime _timestamp(Object? value) {
    if (value is! String || value.length > 64) {
      throw const FormatException('AI insight timestamp is invalid.');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw const FormatException('AI insight timestamp is invalid.');
    }
    return parsed.toUtc();
  }

  static void _uuid(Object? value) {
    if (value is! String ||
        !RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(value)) {
      throw const FormatException(
        'AI insight evaluation identifier is invalid.',
      );
    }
  }
}

class _InsightContent {
  final String executiveSummary;
  final List<BusinessEvaluationAiInsightDriver> drivers;
  final List<BusinessEvaluationAiInsightAction> actions;
  final BusinessEvaluationAiInsightScenario scenarioToTest;
  final List<String> dataLimitations;
  final String disclaimer;

  const _InsightContent({
    required this.executiveSummary,
    required this.drivers,
    required this.actions,
    required this.scenarioToTest,
    required this.dataLimitations,
    required this.disclaimer,
  });
}
