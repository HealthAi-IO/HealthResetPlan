import 'package:flutter/material.dart';

class SecurePasswordField extends StatefulWidget {
  const SecurePasswordField({
    super.key,
    required this.controller,
    this.labelText = '密码',
    this.hintText = '请输入密码',
    this.enabled = true,
    this.errorText,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String labelText;
  final String hintText;
  final bool enabled;
  final String? errorText;
  final ValueChanged<String>? onSubmitted;

  @override
  State<SecurePasswordField> createState() => _SecurePasswordFieldState();
}

class _SecurePasswordFieldState extends State<SecurePasswordField>
    with WidgetsBindingObserver {
  final FocusNode _focusNode = FocusNode();
  final FocusNode _visibilityFocusNode = FocusNode(
    skipTraversal: true,
    canRequestFocus: false,
  );
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _hidePassword();
    }
  }

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _hidePassword();
    }
  }

  void _hidePassword() {
    if (!_obscureText && mounted) {
      setState(() => _obscureText = true);
    }
  }

  void _toggleVisibility() {
    final selection = widget.controller.selection;
    final hadFocus = _focusNode.hasFocus;
    setState(() => _obscureText = !_obscureText);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (hadFocus) {
        _focusNode.requestFocus();
      }
      if (selection.isValid) {
        widget.controller.selection = selection;
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    _visibilityFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      obscureText: _obscureText,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.visiblePassword,
      autofillHints: const [AutofillHints.password],
      textInputAction: TextInputAction.done,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        errorText: widget.errorText,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          focusNode: _visibilityFocusNode,
          tooltip: _obscureText ? '显示密码' : '隐藏密码',
          onPressed: widget.enabled ? _toggleVisibility : null,
          icon: Icon(
            _obscureText
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
      ),
    );
  }
}
