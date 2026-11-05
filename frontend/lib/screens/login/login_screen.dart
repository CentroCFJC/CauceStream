/// Pantalla de inicio de sesion.
///
/// Reproduce la referencia login_cauce_stream (Stitch): badge de LAN,
/// logo completo, tarjeta de acceso con correo + PIN de 4 digitos y
/// estados de carga/exito/error. La autenticacion es real contra
/// POST /api/auth/login del backend FastAPI.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/cauce_colors.dart';
import '../../core/app_info.dart';
import '../../core/theme/cauce_theme.dart';
import '../../session/session_controller.dart';
import '../../widgets/identity_widgets.dart';
import '../../widgets/organic_background.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _emailFocus = FocusNode();
  final _formKey = GlobalKey<FormState>();

  /// Cuatro digitos del PIN, uno por casilla.
  final List<TextEditingController> _pinControllers = List.generate(
    4,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _pinFocus = List.generate(4, (_) => FocusNode());

  /// Valor previo de cada casilla del PIN: permite distinguir un
  /// digito nuevo de un reemplazo sobre una casilla ya ocupada.
  final List<String> _previousPin = List.filled(4, '');

  bool _rememberEmail = true;
  bool _submitting = false;

  /// null = sin mensaje; color + texto en caso contrario.
  (Color, Color, String)? _feedback;

  @override
  void initState() {
    super.initState();
    final remembered = context.read<SessionController>().email;
    if (remembered != null && remembered.isNotEmpty) {
      _emailController.text = remembered;
    }
    _emailFocus.addListener(_onEmailFocusChanged);
  }

  /// Al entrar al campo (tab o tap) el cursor queda al inicio: lo
  /// que se corrige es el usuario, no el dominio institucional.
  void _onEmailFocusChanged() {
    if (_emailFocus.hasFocus) {
      _emailController.selection = TextSelection.collapsed(offset: 0);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocus.dispose();
    for (final c in _pinControllers) {
      c.dispose();
    }
    for (final f in _pinFocus) {
      f.dispose();
    }
    super.dispose();
  }

  String get _pin => _pinControllers.map((c) => c.text).join();

  /// Patron del contrato real: PIN numerico de 4 digitos
  /// (app/schemas/common.py, `^\d{4}$`).
  bool get _pinComplete => RegExp(r'^\d{4}$').hasMatch(_pin);

  Future<void> _submit() async {
    // Evita solicitudes duplicadas mientras se procesa una autenticacion.
    if (_submitting) return;

    final email = _emailController.text.trim();
    if (!_formKey.currentState!.validate()) return;

    if (!_pinComplete) {
      setState(() {
        _feedback = (
          const Color(0xFFFFF1F2),
          const Color(0xFF9F1239),
          'Por favor ingresa los 4 digitos completos de tu PIN.',
        );
      });
      return;
    }

    setState(() {
      _submitting = true;
      _feedback = (
        const Color(0xFFECFDF5),
        const Color(0xFF065F46),
        'Conectando al servidor local de sala...',
      );
    });

    final session = context.read<SessionController>();
    // ignore: use_build_context_synchronously
    final ok = await session.login(
      email: email,
      pin: _pin,
      rememberEmail: _rememberEmail,
    );

    if (!mounted) return;
    if (ok) {
      // La SessionGate detecta el cambio de estado y navega al inicio.
      for (final c in _pinControllers) {
        c.clear();
      }
      setState(() {
        _submitting = false;
        _feedback = null;
      });
      return;
    }

    setState(() {
      _submitting = false;
      _feedback = (
        const Color(0xFFFFF1F2),
        const Color(0xFF9F1239),
        session.lastAuthError ?? 'No fue posible iniciar sesion.',
      );
    });
  }

  /// Extrae el digito que se acabo de insertar: `next` es `previous`
  /// con un caracter nuevo en alguna posicion.
  String _insertedDigit(String previous, String next) {
    for (var i = 0; i < next.length; i++) {
      if (i >= previous.length || previous[i] != next[i]) {
        return next[i];
      }
    }
    return '';
  }

  void _onPinChanged(int index, String value) {
    // Un solo digito por casilla, con avance automatico. Se compara
    // con el valor previo para no confundir un reemplazo (escribir
    // sobre una casilla ocupada) con un relleno rapido (pegado).
    final previous = _previousPin[index];
    final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly == previous) return;

    if (digitsOnly.length - previous.length > 1) {
      // Relleno rapido: distribuye los digitos escritos.
      var cursor = index;
      for (final digit in digitsOnly.split('')) {
        if (cursor > 3) break;
        _pinControllers[cursor].text = digit;
        _previousPin[cursor] = digit;
        cursor++;
      }
      _pinFocus[cursor > 3 ? 3 : cursor].requestFocus();
      return;
    }

    if (previous.isNotEmpty && digitsOnly.length == previous.length + 1) {
      // Se escribio un digito sobre una casilla ocupada: reemplaza
      // el digito y avanza una sola casilla.
      final digit = _insertedDigit(previous, digitsOnly);
      _pinControllers[index].text = digit;
      _previousPin[index] = digit;
      if (index < 3) {
        _pinFocus[index + 1].requestFocus();
      }
      return;
    }

    // Digito nuevo en casilla vacia, o borrado.
    _pinControllers[index].text = digitsOnly;
    _previousPin[index] = digitsOnly;
    if (digitsOnly.length == 1 && index < 3) {
      _pinFocus[index + 1].requestFocus();
    }
  }

  void _onPinBackspace(int index) {
    if (_pinControllers[index].text.isEmpty && index > 0) {
      _pinFocus[index - 1].requestFocus();
      _pinControllers[index - 1].clear();
      _previousPin[index - 1] = '';
    }
  }

  /// Tarjeta de acceso compartida por la vista; se monta dentro del
  /// area expandible central.
  Widget _loginForm() {
    return _LoginForm(
      formKey: _formKey,
      emailController: _emailController,
      emailFocus: _emailFocus,
      pinControllers: _pinControllers,
      pinFocus: _pinFocus,
      rememberEmail: _rememberEmail,
      onRememberChanged: (v) => setState(() => _rememberEmail = v),
      onPinChanged: _onPinChanged,
      onPinBackspace: _onPinBackspace,
      pinComplete: _pinComplete,
      submitting: _submitting,
      feedback: _feedback,
      onSubmit: _submit,
      onForgotPin: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solicita un reinicio de PIN con el Administrador Tecnico de Sala.',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Con el teclado abierto la seccion de marca de abajo se oculta:
    // el espacio restante queda para el formulario, sin scroll.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const OrganicBackground(baseColor: CauceColors.cream),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  const _BrandTitle(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Center(
                          // En pantallas cortas el formulario se
                          // encoge en lugar de desbordar: la vista
                          // nunca necesita scroll.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: SizedBox(
                              width: constraints.maxWidth,
                              child: _loginForm(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (!keyboardOpen) ...[
                    const _BrandSection(),
                    const SizedBox(height: 8),
                  ],
                  const _LoginFooter(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Marca de la aplicacion, sola en la franja superior.
class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: 'CAUCE_',
        style: const TextStyle(
          fontFamily: CauceTheme.displayFont,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: CauceColors.darkTeal,
        ),
        children: [
          WidgetSpan(
            child: Transform.translate(
              offset: const Offset(0, 1),
              child: const Text(
                'STREAM',
                style: TextStyle(
                  fontFamily: CauceTheme.displayFont,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: CauceColors.orange,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo y descripcion, bajo toda la seccion de acceso.
class _BrandSection extends StatelessWidget {
  const _BrandSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const LanBadge(),
        const SizedBox(height: 12),
        Image.asset(
          'assets/logo_completo.png',
          width: 120,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 8),
        Text(
          'Plataforma interna para mediadores y operadores de sala',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: CauceTheme.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: CauceColors.brown.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.formKey,
    required this.emailController,
    required this.emailFocus,
    required this.pinControllers,
    required this.pinFocus,
    required this.rememberEmail,
    required this.onRememberChanged,
    required this.onPinChanged,
    required this.onPinBackspace,
    required this.pinComplete,
    required this.submitting,
    required this.feedback,
    required this.onSubmit,
    required this.onForgotPin,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final FocusNode emailFocus;
  final List<TextEditingController> pinControllers;
  final List<FocusNode> pinFocus;
  final bool rememberEmail;
  final ValueChanged<bool> onRememberChanged;
  final void Function(int, String) onPinChanged;
  final void Function(int) onPinBackspace;
  final bool pinComplete;
  final bool submitting;
  final (Color, Color, String)? feedback;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: CauceColors.creamLight,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: CauceColors.brown.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: CauceColors.brown.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Iniciar Sesion',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: CauceTheme.displayFont,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: CauceColors.darkTeal,
              ),
            ),
            const SizedBox(height: 20),
            _emailField(),
            const SizedBox(height: 10),
            _rememberRow(),
            const SizedBox(height: 14),
            _pinHeader(),
            const SizedBox(height: 8),
            _pinGrid(),
            const SizedBox(height: 18),
            _submitButton(),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: onForgotPin,
              child: Text(
                'Olvidaste tu PIN?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: CauceTheme.bodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: CauceColors.teal,
                  decoration: TextDecoration.underline,
                  decorationColor: CauceColors.teal,
                ),
              ),
            ),
            if (feedback != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: feedback!.$1,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: feedback!.$2.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  feedback!.$3,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: feedback!.$2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CORREO INSTITUCIONAL',
          style: TextStyle(
            fontFamily: CauceTheme.bodyFont,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: CauceColors.darkTeal,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: emailController,
          focusNode: emailFocus,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          validator: (v) {
            final value = v?.trim() ?? '';
            if (value.isEmpty) return 'Ingresa tu correo institucional.';
            if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) {
              return 'El correo no tiene un formato valido.';
            }
            return null;
          },
          decoration: InputDecoration(
            prefixIcon: const Icon(
              Icons.mail,
              size: 18,
              color: CauceColors.teal,
            ),
            hintText: '@ucaldas.edu.co',
            filled: true,
            fillColor: CauceColors.cream.withValues(alpha: 0.6),
          ),
          style: const TextStyle(fontFamily: CauceTheme.bodyFont, fontSize: 13),
        ),
      ],
    );
  }

  Widget _rememberRow() {
    return Row(
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: Checkbox(
            value: rememberEmail,
            onChanged: (v) => onRememberChanged(v ?? false),
            activeColor: CauceColors.orange,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Recordar mi correo',
          style: TextStyle(
            fontFamily: CauceTheme.bodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: CauceColors.darkTeal,
          ),
        ),
      ],
    );
  }

  Widget _pinHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text.rich(
          TextSpan(
            text: 'PIN DE ACCESO ',
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: CauceColors.darkTeal,
            ),
            children: const [
              TextSpan(
                text: '*',
                style: TextStyle(color: CauceColors.orange),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: CauceColors.teal.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '4 digitos numericos',
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: CauceColors.teal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _pinGrid() {
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Focus(
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.backspace &&
                    pinControllers[i].text.isEmpty) {
                  onPinBackspace(i);
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: pinControllers[i],
                focusNode: pinFocus[i],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 4,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                autofocus: i == 0,
                style: const TextStyle(
                  fontFamily: CauceTheme.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: CauceColors.darkTeal,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  filled: true,
                  fillColor: CauceColors.cream.withValues(alpha: 0.6),
                ),
                onChanged: (v) => onPinChanged(i, v),
                onSubmitted: (_) {
                  if (pinComplete) onSubmit();
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _submitButton() {
    return FilledButton(
      onPressed: submitting ? null : onSubmit,
      style: FilledButton.styleFrom(
        backgroundColor: submitting
            ? CauceColors.orangeDark
            : CauceColors.orange,
        disabledBackgroundColor: CauceColors.orangeDark,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shadowColor: CauceColors.orange.withValues(alpha: 0.35),
      ),
      child: submitting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            )
          : const Text(
              'Ingresar al Circuito',
              style: TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
    );
  }
}

class _LoginFooter extends StatelessWidget {
  const _LoginFooter();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 14,
                color: Color(0xFF059669),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Autenticacion local aislada en nodo servidor CAUCE',
                    style: TextStyle(
                      fontFamily: CauceTheme.bodyFont,
                      fontSize: 11,
                      color: CauceColors.brown.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Version ${AppInfo.appVersion} • Nodo Central ${AppInfo.serverNode}',
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 10,
              color: Colors.black.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}
