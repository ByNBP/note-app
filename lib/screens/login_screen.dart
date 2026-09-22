import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/feedback.dart';

enum _Mode { signIn, signUp, guest }

/// Giris / kayit / misafir girisi ekrani.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  bool _obscurePassword = true;

  bool get _needsName => _mode != _Mode.signIn;
  bool get _needsEmail => _mode != _Mode.guest;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _busy = true);
    final auth = context.read<AuthService>();
    try {
      switch (_mode) {
        case _Mode.signIn:
          await auth.signIn(
            email: _emailController.text,
            password: _passwordController.text,
          );
        case _Mode.signUp:
          await auth.signUp(
            email: _emailController.text,
            password: _passwordController.text,
            displayName: _nameController.text,
          );
        case _Mode.guest:
          await auth.signInAsGuest(displayName: _nameController.text);
      }
      // Basarili girista yonlendirmeyi router yapar.
    } catch (error) {
      if (mounted) showAppError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ContentShell(
              maxWidth: 440,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.checklist_rounded,
                        size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Ortak Notlar',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bir oturum ac, kodu paylas, herkes ayni listeye not '
                      'eklesin.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SegmentedButton<_Mode>(
                      segments: const [
                        ButtonSegment(
                          value: _Mode.signIn,
                          label: Text('Giris'),
                          icon: Icon(Icons.login),
                        ),
                        ButtonSegment(
                          value: _Mode.signUp,
                          label: Text('Kayit'),
                          icon: Icon(Icons.person_add_alt),
                        ),
                        ButtonSegment(
                          value: _Mode.guest,
                          label: Text('Misafir'),
                          icon: Icon(Icons.bolt),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: _busy
                          ? null
                          : (selection) => setState(() {
                                _mode = selection.first;
                                _formKey.currentState?.reset();
                              }),
                    ),
                    const SizedBox(height: 20),
                    if (_needsName) ...[
                      TextFormField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Gorunen isim',
                          hintText: 'Notlarinda bu isim gorunecek',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                                ? 'Bir isim gir'
                                : null,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_needsEmail) ...[
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'E-posta',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty) return 'E-posta gir';
                          if (!text.contains('@') || !text.contains('.')) {
                            return 'Gecerli bir e-posta gir';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _busy ? null : _submit(),
                        decoration: InputDecoration(
                          labelText: 'Sifre',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword ? 'Goster' : 'Gizle',
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Sifre gir';
                          }
                          if (_mode == _Mode.signUp && value.length < 6) {
                            return 'En az 6 karakter olmali';
                          }
                          return null;
                        },
                      ),
                    ],
                    if (_mode == _Mode.guest)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Misafir hesabi bu cihaza baglidir. Uygulama '
                          'verilerini silersen oturumlarina erisemezsin.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(switch (_mode) {
                              _Mode.signIn => 'Giris yap',
                              _Mode.signUp => 'Hesap olustur',
                              _Mode.guest => 'Misafir olarak devam et',
                            }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
