import 'dart:async';
import 'package:flutter/services.dart';

class TemplateVariable {
  final String name;
  final String? defaultValue;

  TemplateVariable({required this.name, this.defaultValue});
}

class SecretManager {
  static final SecretManager instance = SecretManager._internal();
  SecretManager._internal();

  bool _isSecretModeActive = false;
  bool get isSecretModeActive => _isSecretModeActive;

  Timer? _clearTimer;
  final _countdownController = StreamController<int>.broadcast();
  int _secondsRemaining = 0;

  Stream<int> get onCountdown => _countdownController.stream;
  int get secondsRemaining => _secondsRemaining;

  void toggleSecretMode() {
    _isSecretModeActive = !_isSecretModeActive;
  }

  void setSecretMode(bool active) {
    _isSecretModeActive = active;
  }

  /// Copies a secret text to system clipboard, and sets a timer to clear it.
  Future<void> copySecretText(String secretText, int timeoutSeconds) async {
    _clearTimer?.cancel();
    _secondsRemaining = timeoutSeconds;
    _countdownController.add(_secondsRemaining);

    await Clipboard.setData(ClipboardData(text: secretText));

    _clearTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      _secondsRemaining--;
      if (_secondsRemaining <= 0) {
        timer.cancel();
        _clearTimer = null;
        // Clear clipboard
        await Clipboard.setData(const ClipboardData(text: ''));
        _countdownController.add(0);
      } else {
        _countdownController.add(_secondsRemaining);
      }
    });
  }

  void cancelClearTimer() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _secondsRemaining = 0;
    _countdownController.add(0);
  }

  // ─── Command Template Engine ───────────────────────────────────────────────

  /// Parses variables in the form of {name} or {name=default}
  List<TemplateVariable> parseTemplate(String template) {
    final regExp = RegExp(r'\{([a-zA-Z0-9_]+)(?:=([^}]+))?\}');
    final matches = regExp.allMatches(template);
    final List<TemplateVariable> vars = [];
    final Set<String> seen = {};

    for (final match in matches) {
      final name = match.group(1)!;
      final defaultValue = match.group(2);
      if (!seen.contains(name)) {
        seen.add(name);
        vars.add(TemplateVariable(name: name, defaultValue: defaultValue));
      }
    }
    return vars;
  }

  /// Resolves the template with values
  String resolveTemplate(String template, Map<String, String> values) {
    final regExp = RegExp(r'\{([a-zA-Z0-9_]+)(?:=([^}]+))?\}');
    return template.replaceAllMapped(regExp, (match) {
      final name = match.group(1)!;
      final defaultValue = match.group(2) ?? '';
      return values[name] ?? defaultValue;
    });
  }
}
