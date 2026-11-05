/// Capacidades de UI derivadas de la sesion.
///
/// El modelo `User` solo expone el rol (los permisos viven en el
/// backend), asi que cada capacidad se decide aqui, en un unico
/// helper, y nunca comprobando nombres de rol dispersos por la app.
/// El backend sigue siendo la autoridad: estas funciones solo
/// ocultan acciones en la interfaz; un 403 del servidor se maneja
/// como red de seguridad.
library;

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../session/session_controller.dart';

/// `content.manage` (subir y eliminar medios): en la configuracion
/// actual del backend solo el rol ADMINISTRADOR lo posee.
bool canManageContent(BuildContext context) =>
    context.select((SessionController s) => s.isAdmin);

/// `devices.control` (encendido/apagado remoto, incluido el control
/// maestro de la sala): en la configuracion actual del backend solo
/// el rol ADMINISTRADOR lo posee. El backend sigue siendo la
/// autoridad: esta funcion solo oculta acciones en la interfaz; un
/// 403 del servidor se maneja como red de seguridad.
bool canControlDevices(BuildContext context) =>
    context.select((SessionController s) => s.isAdmin);
