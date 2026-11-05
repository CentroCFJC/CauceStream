/// Datos estaticos de demostracion.
///
/// IMPORTANTE: contenido provisional. Solo existe para conservar la
/// composicion visual de las pantallas base mientras los modulos de
/// dispositivos, medios y actividades no se integran con la API
/// (fase 1 = solo interfaz y navegacion). Ningun dato de aqui debe
/// confundirse con informacion real de la sala.
library;

import 'package:flutter/material.dart';

import '../core/theme/cauce_colors.dart';
import '../widgets/identity_widgets.dart';

class DemoDevice {
  const DemoDevice({
    required this.name,
    required this.category,
    required this.subtitle,
    required this.status,
    required this.statusLabel,
    required this.footerLeft,
    required this.footerRight,
    this.ip,
    this.online = true,
  });

  final String name;
  final String category;
  final String subtitle;
  final CauceStatus status;
  final String statusLabel;
  final String footerLeft;
  final String footerRight;
  final String? ip;
  final bool online;
}

class DemoActivity {
  const DemoActivity({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.relativeTime,
    required this.description,
    required this.accent,
    required this.icon,
    this.tagLabel,
    this.isAlert = false,
  });

  final String title;
  final String subtitle;
  final String time;
  final String relativeTime;
  final String description;
  final Color accent;
  final IconData icon;
  final String? tagLabel;
  final bool isAlert;
}

abstract final class DemoData {
  /// Inventario visible en la pestana Dispositivos.
  static const devices = <DemoDevice>[
    DemoDevice(
      name: 'Muro LED Curvo',
      category: 'Pantalla',
      subtitle: "'Cosmos_4K.mp4' en bucle",
      status: CauceStatus.online,
      statusLabel: 'En linea',
      footerLeft: '10.15.1.160',
      footerRight: '',
      ip: '10.15.1.160',
    ),
    DemoDevice(
      name: 'Casco VR 01',
      category: 'VR',
      subtitle: "'Simulacion Marte'",
      status: CauceStatus.online,
      statusLabel: 'Conectado',
      footerLeft: 'Bateria 88%',
      footerRight: 'Gafas Standalone #01',
      ip: '10.15.1.161',
    ),
    DemoDevice(
      name: 'Totem Circuito Central',
      category: 'Totem',
      subtitle: 'Mapa Interactivo Guia',
      status: CauceStatus.online,
      statusLabel: 'En linea',
      footerLeft: '10.15.1.170',
      footerRight: 'Totem 43" 4K',
      ip: '10.15.1.170',
    ),
    DemoDevice(
      name: 'Mesa Tactil Sala Sur',
      category: 'Tactil',
      subtitle: 'Catalogo Patrimonio 3D',
      status: CauceStatus.alert,
      statusLabel: 'Latencia',
      footerLeft: '10.15.1.152',
      footerRight: '340 ms',
      ip: '10.15.1.152',
    ),
    DemoDevice(
      name: 'TV Sala Norte',
      category: 'Television',
      subtitle: 'Sin senal de video',
      status: CauceStatus.offline,
      statusLabel: 'Desconectado',
      footerLeft: 'Ultimo latido hace 3 min',
      footerRight: '',
      ip: '10.15.1.42',
      online: false,
    ),
    DemoDevice(
      name: 'Estacion Audio Guiado',
      category: 'Audio',
      subtitle: 'Reproduciendo pista 03',
      status: CauceStatus.active,
      statusLabel: 'Activo',
      footerLeft: 'Capitulo 3: La Cuenca del Saber',
      footerRight: 'Vol 75%',
      ip: '10.15.1.180',
    ),
  ];

  /// Estaciones destacadas en la pantalla de Inicio.
  static const homeStations = <DemoDevice>[
    DemoDevice(
      name: 'Mapa Interactivo de Cuencas',
      category: 'Totem Interactivo',
      subtitle: '',
      status: CauceStatus.online,
      statusLabel: 'En linea',
      footerLeft: '',
      footerRight: '',
    ),
    DemoDevice(
      name: 'El Cauce que Respira (360)',
      category: 'VR Inmersivo 01',
      subtitle: '',
      status: CauceStatus.online,
      statusLabel: 'En linea',
      footerLeft: '',
      footerRight: '',
    ),
    DemoDevice(
      name: 'Viaje al Fondo Fluvial',
      category: 'VR Inmersivo 02',
      subtitle: '',
      status: CauceStatus.online,
      statusLabel: 'En linea',
      footerLeft: '',
      footerRight: '',
    ),
    DemoDevice(
      name: 'Ecosistemas del Rio Cauca',
      category: 'Mesa Tactil Interactiva',
      subtitle: '',
      status: CauceStatus.alert,
      statusLabel: 'Revisar',
      footerLeft: '',
      footerRight: '',
    ),
    DemoDevice(
      name: 'Biofonia y Murmullo del Agua',
      category: 'Paisaje Sonoro',
      subtitle: '',
      status: CauceStatus.online,
      statusLabel: 'En linea',
      footerLeft: '',
      footerRight: '',
    ),
    DemoDevice(
      name: 'Fauna Fluvial Holografica',
      category: 'Estacion AR 01',
      subtitle: '',
      status: CauceStatus.online,
      statusLabel: 'En linea',
      footerLeft: '',
      footerRight: '',
    ),
    DemoDevice(
      name: 'Catalogo Abierto de Saberes',
      category: 'Repositorio CAUCE',
      subtitle: '',
      status: CauceStatus.online,
      statusLabel: 'En linea',
      footerLeft: '',
      footerRight: '',
    ),
    DemoDevice(
      name: 'Resonancia Hidrologica',
      category: 'Domo Acustico',
      subtitle: '',
      status: CauceStatus.online,
      statusLabel: 'En linea',
      footerLeft: '',
      footerRight: '',
    ),
  ];

  /// Actividades y alertas.
  static const activities = <DemoActivity>[
    DemoActivity(
      title: 'Alerta de Temperatura',
      subtitle: 'Muro LED Principal • Panel Centro-Sur',
      time: '11:42 AM',
      relativeTime: 'hace 3 min',
      description:
          'Advertencia termica alcanzo 68 C (umbral seguro: 65 C). Modulos de ventilacion forzada 3 y 4 activados al 100%.',
      accent: CauceColors.maroon,
      icon: Icons.device_thermostat,
      tagLabel: 'UMBRAL CRITICO',
      isAlert: true,
    ),
    DemoActivity(
      title: 'Cambio de Medio',
      subtitle: 'TV Sala Norte • Pantalla Interactiva',
      time: '11:30 AM',
      relativeTime: 'hace 15 min',
      description:
          'Reproduciendo ahora 01_Biodiversidad_Cuenca_Magdalena (Video UHD 4K, 60fps, bucle activo).',
      accent: CauceColors.creamSecondary,
      icon: Icons.movie,
    ),
    DemoActivity(
      title: 'Conexion Restablecida',
      subtitle: 'Totem Tactil 02 • Estacion Central',
      time: '10:18 AM',
      relativeTime: 'hace 1h 27m',
      description:
          'Conexion reconectada exitosamente en IP 10.15.1.42 con 4ms de latencia. Sincronizacion completa.',
      accent: CauceColors.teal,
      icon: Icons.cloud_done,
    ),
    DemoActivity(
      title: 'Perdida de Conexion',
      subtitle: 'Totem Tactil 02 • Estacion Central',
      time: '10:15 AM',
      relativeTime: 'hace 1h 30m',
      description:
          'Sin respuesta en IP 10.15.1.42 (timeout 3000ms). Se iniciaron reintentos automaticos.',
      accent: CauceColors.maroon,
      icon: Icons.wifi_off,
      tagLabel: 'Resuelto automaticamente',
      isAlert: true,
    ),
    DemoActivity(
      title: 'Dispositivo en Standby',
      subtitle: 'Casco VR Estacion 1 • Modulo Inmersivo',
      time: '09:45 AM',
      relativeTime: 'hace 2h',
      description:
          'Suspension automatica activada por inactividad del sensor de proximidad tras 15 min sin interaccion.',
      accent: CauceColors.creamTertiary,
      icon: Icons.power_off,
    ),
    DemoActivity(
      title: 'Dispositivo Encendido',
      subtitle: 'Proyector Mapeo Techo • Sala',
      time: '09:00 AM',
      relativeTime: 'Apertura',
      description:
          'Dispositivo encendido exitosamente por comando maestro de apertura de sala (IP 10.15.1.185).',
      accent: CauceColors.creamPrimary,
      icon: Icons.power_settings_new,
    ),
  ];

  /// Actividad reciente de la pantalla de Inicio.
  static const recentActivity = <DemoActivity>[
    DemoActivity(
      title: 'Interaccion iniciada en VR 03',
      subtitle: 'Experiencia: "El cauce que respira"',
      time: '',
      relativeTime: 'Hace 2m',
      description: '',
      accent: CauceColors.teal,
      icon: Icons.touch_app,
    ),
    DemoActivity(
      title: 'Retardo detectado en Mesa Tactil',
      subtitle: 'Reordenando paquetes locales',
      time: '',
      relativeTime: 'Hace 8m',
      description: '',
      accent: CauceColors.peachSecondaryContainer,
      icon: Icons.speed,
    ),
    DemoActivity(
      title: 'Paisaje Sonoro sincronizado',
      subtitle: 'Capsula de biofonia del rio iniciada',
      time: '',
      relativeTime: 'Hace 15m',
      description: '',
      accent: CauceColors.teal,
      icon: Icons.podcasts,
    ),
  ];
}
