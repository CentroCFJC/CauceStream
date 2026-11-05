/// Pantalla de Perfil y Sesion.
///
/// Integracion real dentro de los contratos disponibles:
/// - El backend no expone `/users/me`; el id del usuario se decodifica
///   del JWT y se consulta GET /api/users/{id}.
/// - ADMINISTRADOR posee `users.view` y el permiso de gestion de su
///   rol, por lo que ve su perfil completo y puede editar nombre,
///   correo y PIN (PATCH /api/users/{id}).
/// - MEDIADOR recibe 403 en ambas operaciones: perfil de SOLO LECTURA
///   con los datos disponibles localmente (correo del login + token).
/// - No existe endpoint de logout: cerrar sesion elimina el token
///   almacenado localmente y redirige al login.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_info.dart';
import '../../core/theme/cauce_colors.dart';
import '../../core/theme/cauce_theme.dart';
import '../../models/user.dart';
import '../../session/session_controller.dart';
import '../../widgets/cauce_headers.dart';
import '../../widgets/organic_background.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _loading = true;
  bool _restricted = false;
  bool _networkError = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _networkError = false;
    });
    final result = await context.read<SessionController>().loadProfile();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _restricted = result == ProfileLoadResult.restricted;
      _networkError = result == ProfileLoadResult.networkError;
    });
  }

  Future<void> _confirmLogout() async {
    final session = context.read<SessionController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cerrar Sesion de Mediacion?'),
        content: const Text(
          'Se eliminara el token de acceso guardado en este dispositivo y '
          'volveras a la pantalla de ingreso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: CauceColors.maroon),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await session.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final user = session.user;
    final isAdmin = session.isAdmin;

    return Scaffold(
      backgroundColor: CauceColors.creamSurface,
      body: Stack(
        children: [
          const OrganicBackground(baseColor: CauceColors.creamSurface),
          Column(
            children: [
              const StackHeader(
                title: 'Perfil & Sesion',
                closeInsteadOfBack: true,
                subtitle: 'CAUCE_STREAM',
                showLanBadge: false,
                backgroundColor: CauceColors.creamSurface,
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadProfile,
                  // SafeArea inferior: garantiza que el contenido
                  // termine sobre la barra de gestos del telefono,
                  // igual que la barra de navegacion del shell.
                  child: SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_loading)
                            const _LoadingCard()
                          else if (_networkError)
                            _ErrorCard(onRetry: _loadProfile)
                          else
                            _IdentityCard(
                              user: user,
                              email: session.email ?? '',
                              restricted: _restricted,
                              isAdmin: isAdmin,
                            ),
                          const SizedBox(height: 16),
                          if (!_loading && !_networkError && user != null) ...[
                            _AccountInfoCard(user: user),
                            const SizedBox(height: 16),
                          ],
                          const _AlertsCard(),
                          const SizedBox(height: 16),
                          _SecurityCard(
                            isAdmin: isAdmin,
                            restricted: _restricted,
                          ),
                          const SizedBox(height: 8),
                          _LogoutButton(onConfirmLogout: _confirmLogout),
                          const SizedBox(height: 8),
                          _VersionFooter(restricted: _restricted),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: CauceColors.creamSurfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: CauceColors.creamSecondary),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CauceColors.peachErrorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.wifi_off, size: 32, color: CauceColors.error),
          const SizedBox(height: 8),
          const Text(
            'No fue posible contactar el servidor Cauce',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: CauceColors.creamOnSurface,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Verifica que el nodo central este disponible en la LAN.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 13,
              color: CauceColors.creamOnSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.user,
    required this.email,
    required this.restricted,
    required this.isAdmin,
  });

  final User? user;
  final String email;
  final bool restricted;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final name = user?.name ?? 'Usuario de Sala';
    final shownEmail = user?.email ?? email;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CauceColors.creamSurfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                width: 64,
                height: 64,
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: CauceColors.creamSecondaryFixed,
                  shape: BoxShape.circle,
                ),
                child: Image.asset('assets/logo_iso.png', fit: BoxFit.contain),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: CauceColors.creamSurfaceContainerLow,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: CauceTheme.displayFont,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: CauceColors.creamOnSurface,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.circle, size: 6, color: Color(0xFF047857)),
                          SizedBox(width: 4),
                          Text(
                            'Activa',
                            style: TextStyle(
                              fontFamily: CauceTheme.bodyFont,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF065F46),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  // Rol mostrado: real cuando el backend lo permite;
                  // para un token sin acceso a /users se infiere
                  // "Mediador" (unico otro rol del dominio).
                  restricted
                      ? 'Mediador'
                      : (isAdmin ? 'Administrador' : 'Mediador'),
                  style: const TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: CauceColors.creamOnSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.mail_outline,
                      size: 14,
                      color: CauceColors.creamTertiary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        shownEmail,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: CauceTheme.bodyFont,
                          fontSize: 12,
                          color: CauceColors.creamTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountInfoCard extends StatelessWidget {
  const _AccountInfoCard({required this.user});

  final User user;

  String _formatDate(DateTime date) {
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CauceColors.creamSurfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Datos de la cuenta',
            style: TextStyle(
              fontFamily: CauceTheme.displayFont,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: CauceColors.creamOnSurface,
            ),
          ),
          const SizedBox(height: 10),
          _AccountRow(
            label: 'Rol',
            value: user.isAdmin ? 'ADMINISTRADOR' : 'MEDIADOR',
          ),
          _AccountRow(label: 'ID de usuario', value: '${user.id}'),
          _AccountRow(label: 'Creado', value: _formatDate(user.createdAt)),
          _AccountRow(
            label: 'Ultima actualizacion',
            value: _formatDate(user.updatedAt),
          ),
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 13,
              color: CauceColors.creamOnSurfaceVariant,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CauceColors.creamOnSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertsCard extends StatefulWidget {
  const _AlertsCard();

  @override
  State<_AlertsCard> createState() => _AlertsCardState();
}

class _AlertsCardState extends State<_AlertsCard> {
  bool _lanAlerts = true;
  bool _sync = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CauceColors.creamSurfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Alertas y notificaciones',
                  style: TextStyle(
                    fontFamily: CauceTheme.displayFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: CauceColors.creamOnSurface,
                  ),
                ),
              ),
              Icon(
                Icons.notifications,
                size: 20,
                color: CauceColors.creamTertiary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AlertSwitch(
            icon: Icons.campaign,
            title: 'Alertas de Red Local',
            subtitle: 'Avisos ante desconexion de nodos',
            value: _lanAlerts,
            onChanged: (v) => setState(() => _lanAlerts = v),
          ),
          const SizedBox(height: 8),
          _AlertSwitch(
            icon: Icons.sync,
            title: 'Sincronizacion Continua',
            subtitle: 'Intercambio de metricas en segundo plano',
            value: _sync,
            onChanged: (v) => setState(() => _sync = v),
          ),
        ],
      ),
    );
  }
}

class _AlertSwitch extends StatelessWidget {
  const _AlertSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CauceColors.creamSurfaceContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 22, color: CauceColors.creamSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: CauceColors.creamOnSurface,
                  ),
                ),
                Text(
                  subtitle,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 13,
                    color: CauceColors.creamOnSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: CauceColors.creamSecondary,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard({required this.isAdmin, required this.restricted});

  final bool isAdmin;
  final bool restricted;

  void _openPinDialog(BuildContext context) {
    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Solo un administrador puede actualizar el PIN desde este perfil.',
          ),
        ),
      );
      return;
    }
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Actualizar PIN de Seguridad'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'El nuevo PIN debe tener exactamente 4 digitos numericos.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                counterText: '',
                hintText: '****',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              final pin = controller.text.trim();
              if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('El PIN debe tener 4 digitos numericos.'),
                  ),
                );
                return;
              }
              final session = context.read<SessionController>();
              Navigator.of(dialogContext).pop();
              final updated = await session.updateOwnProfile(pin: pin);
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    updated != null
                        ? 'PIN actualizado correctamente.'
                        : 'El servidor rechazo la operacion.',
                  ),
                ),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _openEditDialog(BuildContext context) {
    if (!isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tu perfil es de solo lectura con el rol MEDIADOR.'),
        ),
      );
      return;
    }
    final session = context.read<SessionController>();
    final user = session.user;
    if (user == null) return;
    final nameController = TextEditingController(text: user.name);
    final emailController = TextEditingController(text: user.email);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Editar perfil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              final updated = await session.updateOwnProfile(
                name: nameController.text.trim(),
                email: emailController.text.trim(),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    updated != null
                        ? 'Perfil actualizado correctamente.'
                        : 'El servidor rechazo la operacion.',
                  ),
                ),
              );
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: CauceColors.creamSurfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Seguridad de Acceso',
                style: TextStyle(
                  fontFamily: CauceTheme.displayFont,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: CauceColors.creamOnSurface,
                ),
              ),
            ),
          ),
          _SecurityRow(
            icon: Icons.pin,
            iconBg: CauceColors.creamSecondary.withValues(alpha: 0.12),
            iconColor: CauceColors.creamSecondary,
            label: 'Actualizar PIN de Seguridad',
            onTap: () => _openPinDialog(context),
          ),
          const SizedBox(height: 6),
          _SecurityRow(
            icon: Icons.edit,
            iconBg: CauceColors.creamSecondary.withValues(alpha: 0.12),
            iconColor: CauceColors.creamSecondary,
            label: 'Editar nombre y correo',
            onTap: () => _openEditDialog(context),
          ),
          const SizedBox(height: 6),
          _SecurityRow(
            icon: Icons.report_problem,
            iconBg: CauceColors.yellow.withValues(alpha: 0.2),
            iconColor: CauceColors.creamOnSurface,
            label: 'Notificar Incidencia Tecnica',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'El registro de incidencias llegara en una fase posterior.',
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SecurityRow extends StatelessWidget {
  const _SecurityRow({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: CauceTheme.bodyFont,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: CauceColors.creamOnSurface,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: CauceColors.creamOnSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.onConfirmLogout});

  final VoidCallback onConfirmLogout;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onConfirmLogout,
      style: FilledButton.styleFrom(
        backgroundColor: CauceColors.maroon,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: const Icon(Icons.logout, size: 20),
      label: const Text(
        'Cerrar Sesion Activa',
        style: TextStyle(
          fontFamily: CauceTheme.bodyFont,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter({required this.restricted});

  final bool restricted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: CauceColors.creamSecondary,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              '${AppInfo.appName} ${AppInfo.appVersion}',
              style: TextStyle(
                fontFamily: CauceTheme.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: CauceColors.creamSecondary,
              ),
            ),
          ],
        ),
        if (restricted) ...[
          const SizedBox(height: 6),
          Text(
            'Perfil de solo lectura: el backend no expone el detalle de '
            'usuarios para el rol MEDIADOR.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: CauceTheme.bodyFont,
              fontSize: 11,
              color: CauceColors.creamOnSurfaceVariant.withValues(alpha: 0.7),
            ),
          ),
        ],
      ],
    );
  }
}
